#include "esp_camera.h"

#include "soc/soc.h"           // Disable brownout problems
#include "soc/rtc_cntl_reg.h"  // Disable brownout problems
#include "driver/rtc_io.h"

#define CAMERA_MODEL_AI_THINKER

#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

#define STATUS_LED        33
#define MODE_PIN          16

#define PREAMBEL 144
#define RANGE_MAX 10
#define MAX_ROWS 600

struct Peak {
  uint16_t row;
  uint32_t sum;
  uint16_t upper_extent;
};
  
Peak peaks[MAX_ROWS]; // Array to store detected peaks

uint16_t peak_count = 0;
uint8_t min_dist = 0; // when next peak is less than 10 rows apart merge

camera_fb_t* fb = NULL;
uint16_t get_max_location(camera_fb_t* fb, bool debug_out);
uint16_t get_max_multiple(camera_fb_t* fb, bool debug_out);
void blinkLED(uint8_t repeats, uint16_t delay_on, uint16_t delay_off);

uint16_t location = 0;
uint16_t scan_lim_high = 0;
uint16_t scan_lim_low = 0;
uint32_t min_thresh = 0;
uint8_t min_pix_val = 0;
uint8_t peak_id = 0;

uint8_t start_marker_buf[8];
uint8_t end_marker_buf[8];
uint8_t location_buf[2];

uint8_t peak_buf[2];

uint8_t uart_send_lvl = 0;
uint8_t debug_send_bt = 0; // if 255 then initialise, if 1 then send every image and so on
char device_name_bt[12] = "inkulevel_X"; // C-strings have terminating 0
uint8_t inkulevel_pos = 0; // init all with 0 and then set with first command
uint8_t uart_inkulevel_before[4] = {2,3,1,0}; // get the poisiton in the uart chain from the id (index with id and get the uart position)
uint8_t uart_pos[4] = {3,2,0,1};  // get the id from the position in the uart chain (index with uart position and get the id)
char inkulevel_names[5] = "ABCD";

// daisy chain variables
uint8_t preambel = 0;
uint8_t wait = 1;
char control_word;
char command_id;
char command_word;
uint8_t level_sent[4] = {0, 0, 0, 0};

uint8_t send_bt_counter = 0;

// for BT
#include "esp_bt_main.h"
#include "esp_bt_device.h"
#include "esp_gap_bt_api.h"

#include "BluetoothSerial.h"
BluetoothSerial SerialBT;
// end for BT

// https://forum.arduino.cc/t/esp32_cam-acces-and-process-image/677628/5 (211008, this function)
size_t jpgCallBack(void * arg, size_t index, const void* data, size_t len)
{
  uint8_t* basePtr = (uint8_t*) data;
  BluetoothSerial * bt = (BluetoothSerial *)arg; 
  (*bt).write(basePtr, len); // payload (image), payload length
  return 0;
}

bool initBluetooth(const char *deviceName) {
  if (!btStart()) {
    // Serial.println("Failed to initialize controller");
    return false;
  } 
  if (esp_bluedroid_init()!= ESP_OK) {
    // Serial.println("Failed to initialize bluedroid");
    return false;
  } 
  if (esp_bluedroid_enable()!= ESP_OK) {
    // Serial.println("Failed to enable bluedroid");
    return false;
  } 
  esp_bt_dev_set_device_name(deviceName);
  esp_bt_gap_set_scan_mode(ESP_BT_SCAN_MODE_CONNECTABLE_DISCOVERABLE);
}
 
void printDeviceAddress() {
  const uint8_t* point = esp_bt_dev_get_address();
  for (int i = 0; i < 6; i++) {
    char str[3];
    sprintf(str, "%02X", (int)point[i]);
    Serial.print(str);
    if (i < 5){
      Serial.print(":");
    }
  }
}

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0); //disable brownout detector

  Serial.begin(9600);

  //Initialize the camera  
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  // config.pixel_format = PIXFORMAT_JPEG;
  config.pixel_format = PIXFORMAT_GRAYSCALE;

  config.frame_size = FRAMESIZE_SVGA;
  config.fb_count = 1;

  pinMode(STATUS_LED, OUTPUT);
  digitalWrite(STATUS_LED, LOW); 
  pinMode(MODE_PIN, OUTPUT);
  digitalWrite(MODE_PIN, LOW); 

  // camera init
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    // Serial.printf("Camera init failed with error 0x%x", err);
    blinkLED(200, 100, 50);
    return;
  }
  
  sensor_t * s = esp_camera_sensor_get();

  s->set_brightness(s, -1);     // -2 to 2
  s->set_contrast(s, 0);       // -2 to 2
  s->set_saturation(s, 0);     // -2 to 2
  s->set_special_effect(s, 0); // 0 to 6 (0 - No Effect, 1 - Negative, 2 - Grayscale, 3 - Red Tint, 4 - Green Tint, 5 - Blue Tint, 6 - Sepia)
  s->set_whitebal(s, 0);       // 0 = disable , 1 = enable
  s->set_awb_gain(s, 0);       // 0 = disable , 1 = enable
  s->set_wb_mode(s, 0);        // 0 to 4 - if awb_gain enabled (0 - Auto, 1 - Sunny, 2 - Cloudy, 3 - Office, 4 - Home)
  s->set_exposure_ctrl(s, 0);  // 0 = disable , 1 = enable
  s->set_aec2(s, 0);           // 0 = disable , 1 = enable
  s->set_ae_level(s, 0);       // -2 to 2
  s->set_aec_value(s, 0);    // 0 to 1200
  s->set_gain_ctrl(s, 0);      // 0 = disable , 1 = enable
  s->set_agc_gain(s, 0);       // 0 to 30
  s->set_gainceiling(s, (gainceiling_t)0);  // 0 to 6
  s->set_bpc(s, 0);            // 0 = disable , 1 = enable
  s->set_wpc(s, 0);            // 0 = disable , 1 = enable
  s->set_raw_gma(s, 0);        // 0 = disable , 1 = enable
  s->set_lenc(s, 0);           // 0 = disable , 1 = enable
  s->set_hmirror(s, 0);        // 0 = disable , 1 = enable
  s->set_vflip(s, 0);          // 0 = disable , 1 = enable
  s->set_dcw(s, 0);            // 0 = disable , 1 = enable
  s->set_colorbar(s, 0);       // 0 = disable , 1 = enable
  // drop down frame size for higher initial frame rate
  // s->set_framesize(s, FRAMESIZE_SVGA);

  // these are the start and end markers for bluetooth communication
  start_marker_buf[0] = 240;
  end_marker_buf[0] = 225;
  start_marker_buf[1] = 26;
  end_marker_buf[1] = 45;
  start_marker_buf[2] = 226;
  end_marker_buf[2] = 101;
  start_marker_buf[3] = 25;
  end_marker_buf[3] = 154;
  start_marker_buf[4] = 7;
  end_marker_buf[4] = 244;
  start_marker_buf[5] = 189;
  end_marker_buf[5] = 146;
  start_marker_buf[6] = 50;
  end_marker_buf[6] = 111;
  start_marker_buf[7] = 92;
  end_marker_buf[7] = 53;

  location_buf[0] = 0;
  location_buf[1] = 0;

  blinkLED(2, 500, 200);
}

void startBluetooth() {
  initBluetooth(device_name_bt);
  // printDeviceAddress();
  SerialBT.begin(device_name_bt);
}

void stopBluetooth() {
  SerialBT.end(); // This will turn off Bluetooth
}

void daisyChainSend(uint8_t max_cycles) {
  level_sent[0] = 0;
  level_sent[1] = 0;
  level_sent[2] = 0;
  level_sent[3] = 0;
  wait = 1;

  while (wait) {
    if (Serial.available()>2) {
      control_word = Serial.read();
      preambel = (uint8_t(control_word) >> 4);
      if (preambel == 9) { // MSB preambel is correct
        if (control_word & 4) { // if command bit is high interpret the following as command
          // read data
          command_id = Serial.read();
          command_word = Serial.read();
          // check if command is for this inkulevel or should be sent on
          if (control_word & 8) { // this command goes to everyone
            if (command_id == 2) { // this is the assignment command
              inkulevel_pos = uart_pos[command_word]; // assign inkulevel ID depending on uart chain position
              blinkLED(inkulevel_pos+1, 300, 100);
              Serial.print(control_word);
              Serial.print(command_id);
              Serial.print(++command_word); // increase position by 1
            }
          }
          else { 
            // check if command is for me
            if ((control_word % 4) == inkulevel_pos) {
              // execute command
              if (command_id == 0) { // this is the start uart send command
                uart_send_lvl = command_word; // turn on or off
              }
              else if (command_id == 1) { // this is the bluetooth command
                if (command_word) { 
                  if (!debug_send_bt) { // if this was off turn on
                    // update device name and start
                    device_name_bt[10] = inkulevel_names[inkulevel_pos];
                    startBluetooth();
                  }
                }
                else {
                  if (debug_send_bt) { // if this was on turn off
                    stopBluetooth();
                  }
                }
                debug_send_bt = command_word;
                send_bt_counter = 0;
              }
              else if (command_id == 3) {
                scan_lim_low = command_word << 2; // set lower lim to sent value times 4
              }
              else if (command_id == 4) {
                scan_lim_high = command_word << 2; // set lower lim to sent value times 4
              }
              else if (command_id == 5) {
                min_thresh = command_word << 6; // set lower lim to sent value times 64
              }
              else if (command_id == 6) {
                sensor_t * s = esp_camera_sensor_get();
                s->set_aec_value(s, command_word << 2); // set exposure with min 0 and max 1200, value times 4
              }              
              else if (command_id == 7) {
                min_pix_val = command_word;
              }     
              else if (command_id == 8) {
                min_dist = command_word;
              }                 
              else if (command_id == 9) {
                peak_id = command_word; // if 128 take first peak, if 64 take last peak, else select
              }     
              // append more commands here               

              blinkLED(3, 30, 50);
            }
            
            else { // just daisy chain command for another inkulevel
              Serial.print(control_word);
              Serial.print(command_id);
              Serial.print(command_word); 
              blinkLED(2, 10, 10);
            }
          }
        }
        else { // level measurement was received, just send this out
          level_sent[control_word % 4]++; // control_word%4 gives inkulevel position from which this was received
          Serial.print(control_word);
          for (int n = 0; n < 2; n++) {
            Serial.print(char(Serial.read()));    
          }  
          if (level_sent[0]+level_sent[1]+level_sent[2]+level_sent[3] == uart_inkulevel_before[inkulevel_pos]) { // if data was received from all before break
            wait = 0;
          }  
        }    
      }
    }
    else {
      wait = (wait + 1) % max_cycles;
      delay(100); // wait up to 0.1s x max_cycles for daisy chain commands, unless data from all inkulevels before has been received
    }
  }
}

void blinkLED(uint8_t repeats, uint16_t delay_on, uint16_t delay_off) {
  for (uint8_t i = 0; i < repeats; i++) {
    digitalWrite(STATUS_LED, HIGH);  
    delay(delay_on);
    digitalWrite(STATUS_LED, LOW);
    delay(delay_off);
  }
}

uint16_t get_max_multiple(camera_fb_t *fb, bool debug_out) { 
  float tot_count = 0.1;
  float tot_sum   = 0;
  uint8_t flag = 1;

  peak_count = 0;
  uint16_t above_min_pixel = 0;

  location = 0;
  uint16_t start = 0;
  uint32_t max_sum = 0;
  uint32_t current_sum = 0;
  uint8_t info = 0; // this is pre ambel
  if (!scan_lim_high) {
    scan_lim_high = fb->height;
  }

  // scan full image and get max row
  for (int j = scan_lim_low; j < scan_lim_high; j++) { // limit was 0 to fb->height
    current_sum = 0;
    above_min_pixel = 0;
    for (int i = 0; i < int(fb->width); i++) { // search in whole row
        current_sum = current_sum + (fb -> buf)[i+j*fb->width];
        above_min_pixel += ((fb -> buf)[i+j*fb->width] > min_pix_val); // this would be more efficient, why does it not work?
    }
    if ((current_sum > min_thresh) && above_min_pixel) {
      if (peak_count) {
        if ((j - peaks[peak_count-1].upper_extent) > min_dist) { // if distance to last peak is large enough start new peak
          peaks[peak_count].row = j;
          peaks[peak_count].upper_extent = j;
          peaks[peak_count].sum = current_sum;
          peak_count++;
        }
        else {
          peaks[peak_count-1].upper_extent = j;
          if (peaks[peak_count-1].sum < current_sum) {
            peaks[peak_count-1].row = j;
            peaks[peak_count-1].sum = current_sum;
          }
        }
      }
      else {
        peaks[0].row = j;
        peaks[0].upper_extent = j;
        peaks[0].sum = current_sum;
        peak_count = 1;
      }
    }
  }
  
  if (peak_count) { // if peak was detected
    if ((peak_id < 128) && (peak_id < peak_count)) { // select id
      location = peaks[peak_id].row;
    }
    else { // take last one
      location = peaks[peak_count-1].row;
    }

    if (location < RANGE_MAX) {
      start = 0;
    }
    else {
      if (location > fb->height-2*RANGE_MAX-1) {
        start = fb->height-2*RANGE_MAX-1;
      }
      else {
        start = location-RANGE_MAX;
      }
    }
    for (int j = start; j <= start+2*RANGE_MAX; j++) {
      for (int i = int(1./3 * fb->width); i < int(2./3 * fb->width); i++) {
        tot_count = tot_count + static_cast<float>((fb -> buf)[i+j*fb->width])/255;
        tot_sum = tot_sum + (j-start)*static_cast<float>((fb -> buf)[i+j*fb->width])/25.5; // introduce factor 10 for resolution
      }
    }
    float float_location = float(tot_sum/tot_count) + start*10;
    location = int(float_location + .5);
  }

  info = PREAMBEL + flag * 8 + inkulevel_pos;

  if (debug_out) {
      Serial.printf("Detect %u \n", location);
  }

  Serial.print(char(info));
  Serial.print(char((location>>8) % 256));
  Serial.print(char(location % 256));
  return location;
}


void loop() {   
  // Serial.println("Starting");
    // Calculate the total number of chunks

  daisyChainSend(5);
  if (debug_send_bt || uart_send_lvl) {
    digitalWrite(STATUS_LED, HIGH);  
    fb = esp_camera_fb_get();
    digitalWrite(STATUS_LED, LOW);

    if (fb != NULL) {
      if (uart_send_lvl) {
        location = get_max_multiple(fb, false);
      }
      else {
        location = 0;
        peak_count = 0;
      }

      if (debug_send_bt) {
        if (!send_bt_counter) {
          location_buf[0] = (location>>8) % 256;
          location_buf[1] = location % 256;

          peak_buf[0] = (peak_count>>8) % 256;
          peak_buf[1] = peak_count % 256;

          SerialBT.write(start_marker_buf, 8);
          frame2jpg_cb(fb, 80, jpgCallBack, &SerialBT);
          SerialBT.write(location_buf, 2);
          SerialBT.write(peak_buf, 2);

          SerialBT.write(end_marker_buf, 8);
        }
        send_bt_counter = (send_bt_counter + 1) % debug_send_bt;
      }
      else {
        delay(500);
      }

      // Serial.println("Sent message via bluetooth");
      blinkLED(2, 50, 100);
    }
    
    esp_camera_fb_return(fb);
    delay(200);
  }
}
