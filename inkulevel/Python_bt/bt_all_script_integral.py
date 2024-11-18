import bluetooth
import matplotlib.pyplot as plt
import numpy as np
import time
import select
from PIL import Image
import io
from matplotlib.animation import FuncAnimation
import matplotlib.animation
import multiprocessing as mp
import threading
import datetime
import os

SAVE_DATA = True

start_marker = [b'\xf0',b'\x1a',b'\xe2',b'\x19',b'\x07',b'\xbd',b'2',b'\\']
end_marker =  [b'\xe1',b'-',b'e',b'\x9a',b'\xf4',b'\x92',b'o',b'5']     
q = mp.Queue(50)
  
# Assuming you have a bytearray called 'image_data'
# Define the image dimensions (width and height)
width = 800
height = 600

def connect_and_update_image(target_mac_address, id, q):
    # Set the desired timeout value in seconds
    timeout_seconds = 30  # Change this to the desired timeout value
    max_retries = 3

    for retry in range(max_retries):
        client_sock = bluetooth.BluetoothSocket()
        client_sock.setblocking(1)
        client_sock.settimeout(timeout_seconds)

        try:
            client_sock.connect((target_mac_address, 1))

            print(f'Started receive thread for {target_mac_address} at position {id}')
            break  # Connection succeeded, exit the retry loop
        except bluetooth.btcommon.BluetoothError as e:
            print(f'Connection error: {e}')
            time.sleep(1)  # Wait for a moment before retrying

    # Handle the case when all retries fail
    if retry == max_retries - 1:
        print("Failed to establish a Bluetooth connection after multiple retries.")

    counter = 0
    print(f'Started receive thread for {target_mac_address} at position {id}')

    while True:
    
        t0 = time.time()
        # Create a binary buffer to store the received image data
        image_data = bytearray()
        detected_pos = 0
        flag = 1
        start_count = 0
        while start_count < 8:
            d = client_sock.recv(1)
            if d == start_marker[start_count]:
                start_count += 1
            else: 
                start_count = 0

        # Receive image data
        data = bytearray()
        flag = 1
        end_count = 0
        while end_count < 8:
            d = client_sock.recv(1)
            if d == end_marker[end_count]:
                end_count += 1
            else: 
                end_count = 0
            data.extend(d)
        image_data = data[:-12]
        detected_pos = int.from_bytes(data[-12:-10], 'big', signed=False)
        peak_count = int.from_bytes(data[-10:-8], 'big', signed=False)
        
        # print(f"Image data received successfully. Took {(time.time()-t0):.2f} s")
        # Process the received image_data as needed

        # Open the image using Image.open() with BytesIO
        try:
            with io.BytesIO(image_data) as img_buffer:
                image = Image.open(img_buffer)
            
                # Convert the image to a NumPy array
                image_array = np.array(image)
        except Exception as e:
            print(e)
            image_array = np.zeros((height, width))
        counter += 1

        q.put((id, image_array, detected_pos, counter, peak_count))


def update_fig(fig, ax_f, q, max_id): # wait for events and update figure
    all_ims = []
    all_scp = []
    all_counters = []
    all_peak_nums = []

    if SAVE_DATA:
        date_for_filename = datetime.datetime.today().strftime('%Y%m%d')[2:]
        data_folder = f'{date_for_filename}_inkulevel_data'
        save_id = 0        
        if not os.path.isdir('data'):
            os.mkdir('data')
        while os.path.isdir(f'data/{data_folder}_{save_id}'):
            save_id += 1
        os.mkdir(f'data/{data_folder}_{save_id}')
        data_folder = f'data/{data_folder}_{save_id}'

        save_counter = np.zeros(max_id, dtype=int)
        save_max_frames = 100
        save_chunks = 0
        
        data_store_img = np.zeros((max_id,save_max_frames,height))
        data_store_time = np.empty((max_id,save_max_frames), dtype='datetime64[s]')

    for ax_counter in range(max_id):
        ims = ax_f[ax_counter].imshow(np.zeros((height, width)), cmap='gray', vmin=0, vmax=255)
        all_ims.append(ims)
        scp,  = ax_f[ax_counter].plot(width*.35,0,label='detected',ms=10,color='r',marker='x',ls='', zorder=2)
        all_scp.append(scp)
        counter_t = ax_f[ax_counter].text(width*.03, height*.06, f'{0}', c='w', ma='left')
        all_counters.append(counter_t)
        peak_num_t = ax_f[ax_counter].text(width*.9, height*.06, f'{0}', c='r', ma='right')
        all_peak_nums.append(peak_num_t)
    plt.ion()
    plt.pause(0.2)
    print(f'Started update')
    while True:
        try:
            if not q.empty():      
                data = q.get()
                if len(data) == 5:
                    id, image_array, detected_pos, counter, peak_count = data
                    # ax_f[id].imshow(image_array, cmap='gray')
                    all_ims[id].set_data(image_array)
                    # ims.autoscale()

                    # ax_f[id].plot(width*.35,detected_pos/10,label='detected',ms=10,color='r',marker='x',ls='')
                    all_scp[id].set_data(width*.35, detected_pos/10)

                    all_counters[id].set_text(f'{counter}')
                    all_peak_nums[id].set_text(f'{peak_count}')
                    plt.pause(0.05)        
                    fig.canvas.draw()
                    fig.canvas.flush_events()

                    if SAVE_DATA:
                        current_time = np.datetime64(datetime.datetime.now())
                        data_store_img[id,save_counter[id]] = np.sum(image_array, axis=1)
                        data_store_time[id,save_counter[id]] = current_time

                        save_counter[id] += 1
                        if save_counter[id] == save_max_frames:
                            np.savez(f'{data_folder}/img_data_{save_chunks}.npz', timestamps=data_store_time, frames=data_store_img)
                            save_counter = np.zeros(max_id, dtype=int)
                            data_store_img = np.zeros((max_id,save_max_frames,height))
                            data_store_time = np.empty((max_id,save_max_frames), dtype='datetime64[s]')
                            print(f'Saved chunk {save_chunks}')
                            save_chunks += 1
            else:
                time.sleep(.3)

        except Exception as e:
            print(data)
            print(f'Failed because of {e}')
            pass
            

if __name__ == '__main__':

    inkulevel_addresses = {'A': '', 'B': '', 'C': '', 'D': ''}
    inkulevel_names = 'ABCD'
    inkulevel_num = 0
    t_list = []
    event_list = []

    for duration in [8]:
        devices = bluetooth.discover_devices(duration=duration, lookup_names=True)
        print("Devices found: %s" % len(devices))
        print(devices)
        for item in devices:
            if 'inkulevel' in item[1]:
                print(item)
                inkulevel_addresses[item[1][-1]] = item[0]
    
        inkulevel_num = np.sum([len(inkulevel_addresses[a]) > 1 for a in inkulevel_addresses])
        if inkulevel_num == 4:
            break
    print(f' Starting for {inkulevel_num} devices')

    if inkulevel_num:
        nrows = (inkulevel_num // 3) + 1
        ncols = int(inkulevel_num > 1) + 1
        fig, axs = plt.subplots(nrows, ncols, figsize=(12,6))
        
        ax_counter = 0
        if nrows > 1:                
            ax_f = [axs[r,c] for r in range(nrows) for c in range(ncols)]
        else:
            if ncols == 1:
                ax_f = [axs]
            else:
                ax_f = axs

        for id, inkulevel_key in enumerate(inkulevel_names):
            address = inkulevel_addresses[inkulevel_key]
            if len(address):
                ax_f[ax_counter].set_title(inkulevel_names[id])
                
                t = threading.Thread(
                    target=connect_and_update_image, 
                    args=(address, ax_counter, q), 
                    daemon=True,
                )
                t_list.append(t)
                t.start()
                ax_counter += 1

        update_fig(fig, ax_f, q, ax_counter)
       
    else:
        print(f'No inkulevels found')