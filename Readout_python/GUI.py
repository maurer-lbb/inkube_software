
import numpy as np
import multiprocessing as mp
import pyqtgraph as pg
from PyQt6 import QtWidgets, QtGui
from PyQt6.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout
from pyqtgraph.Qt import QtCore
from datetime import datetime

from ctypes import *
from Client_config import (
    MEA_NUM, 
    PLOT_BUF_LEN,
    SPIKE_WAVELET_LEN,
    STATUS_LEN,
    MAX_PKG_ID,
    AXIS_Y_LIM,
    STATUS_Y_LIMITS,
    WAVELET_Y_LIM,
    ELECTRODE_MAPPING,
    PLOT_NETWORKS,
    DETECT_DURATION,
    PLOT_BUF_LEN,
    FS,
    RESPONSE_IMPORTANT_PERIOD,
    STIMULUS_CYCLE,
    SPIKE_WAVELET_NUM, 
    DO_PLOT_SPIKE_WAVELETS, 
    SHARED_NOISE_BINS, 
    SHARED_NOISE_MAX, 
)

class App(QtWidgets.QTabWidget):
    """GUI window containing inkube environment data, volume feedback, and electrophysiology plots"""
    def __init__(
        self,
        update_thread, #: UpdateData,
        update_thread_wavelet, #: UpdateWavelet, 
        update_thresh_bool: mp.Value, 
        plot_network: mp.Value,
        parent=None,
        channel_num=4,
    ):
        super(App, self).__init__(parent)
        self.plot_num = channel_num
        self.dx = -0.9 * PLOT_BUF_LEN / FS * 1000
        self.y_lim = AXIS_Y_LIM
        self.wave_y_lim = WAVELET_Y_LIM
        self.plot_len = PLOT_BUF_LEN / FS * 1000
        self.plot_voltage_bool_gui = True
        self.update_thresh_bool = update_thresh_bool

        self.spike_colours = ["b", "g", "r", "c"]
        self.raster_colours = ["b", "g", "r", "c"]
        self.env_colours = ["b", "g", "r", "c", "w"]

        if not PLOT_NETWORKS:
            self.spike_colours = np.tile(["b", "g", "r", "c"], 15)
            self.raster_colours = np.tile(["b", "g", "r", "c"], 15)
        self.raster_xlim = RESPONSE_IMPORTANT_PERIOD / FS * 1e3
        self.raster_ylim = MAX_PKG_ID // FS
        self.raster_last_index = 0
        self.raster_plot_it = None
        self.last_trigger_spikes = np.array([])
        self.STTRP_lim = 10. # in ms
        self.clear_raster = True
        self.raster_trigger_el = 0

        self.mea_state = 0
        self.network_state = 0

        self.update_th = update_thread
        self.update_th_wavelet = update_thread_wavelet
        self.shared_plot_network = plot_network

        # open mainwindow with signals
        self.mainbox = QWidget()
        self.mainbox.resize(100, channel_num * 5)
        self.addTab(self.mainbox, 'Signals')

        self.canvas = pg.GraphicsLayoutWidget()

        lay = QVBoxLayout(self.mainbox)
        lay.addWidget(self.canvas)

        lay.addWidget(self.createRadioGroup())
        lay.addWidget(self.createRadioGroupNet())

        # open status tab
        self.statusbox = QWidget()
        self.addTab(self.statusbox, 'Status')

        status_lay = QVBoxLayout(self.statusbox)
        self.status_canvas = pg.GraphicsLayoutWidget()       
        status_lay.addWidget(self.status_canvas)

        # open environment tab
        self.envbox = QWidget()
        self.addTab(self.envbox, 'Env')

        env_lay = QVBoxLayout(self.envbox)
        self.env_canvas = pg.GraphicsLayoutWidget()
        env_lay.addWidget(self.env_canvas)
        env_lay.addWidget(self.createEnvInfo())
        env_lay.addWidget(self.createMeaInfo())
        self.dt_env = 60*60 # in s
        self.last_plotted_time = [0,0]
        self.last_plotted_time[0] = datetime.now().timestamp()

        # open raster tab
        self.rasterbox = QWidget()
        self.addTab(self.rasterbox, 'Raster')

        self.raster_canvas = pg.GraphicsLayoutWidget()

        raster_lay = QVBoxLayout(self.rasterbox)
        raster_lay.addWidget(self.raster_canvas)
        raster_lay.addWidget(self.createRadioGroup(cb=False))
        raster_lay.addWidget(self.createRadioGroupNet())
        raster_lay.addWidget(self.createSTTRPGroup())

        # open mainwindow with signals
        self.shapebox = QWidget()
        self.shapebox.resize(100, channel_num * 5)
        self.addTab(self.shapebox, 'Shapes')

        self.shape_canvas = pg.GraphicsLayoutWidget()

        shape_lay = QVBoxLayout(self.shapebox)
        shape_lay.addWidget(self.shape_canvas)


        self.x_voltage = -np.arange(PLOT_BUF_LEN - 1, -1, -1) / FS * 1000
        self.x_spike_wavelet = np.arange(SPIKE_WAVELET_LEN) / FS * 1000
        self.createPlots()
        self.createStatusPlots()
        self.createEnvPlots()

        self.update_th.plot_voltage_bool = False
        self.plot_voltage_bool_gui = False

        self.setWindowTitle("inkube")
        self.setWindowIcon(QtGui.QIcon("icon.png"))

    def createPlots(self):
        self.plt_items = [None for _ in range(self.plot_num)]
        self.plt_items_sig = [None for _ in range(self.plot_num)]
        self.plt_thresh_line = [None for _ in range(self.plot_num)]
        self.scatter_items = [None for _ in range(self.plot_num)]
        self.view_list = [None for _ in range(self.plot_num)]

        self.spike_wavelet_plt_items = [[] for _ in range(self.plot_num)]
        self.spike_view_list = [None for _ in range(self.plot_num)]

        if self.plot_voltage_bool_gui:
            if self.plot_num > 6:
                if self.plot_num > 36:
                    cols = 6
                else:
                    cols = int(np.sqrt(self.plot_num) + 0.99)
                rows = int(self.plot_num / cols + 0.99)
            else:
                cols = self.plot_num
                rows = 1

            v = self.canvas.addPlot(
                row=rows - 1, col=self.plot_num - (rows - 1) * cols - 1
            )
            data_it = pg.PlotDataItem(np.arange(10), np.ones(10))
            sig_it = pg.PlotDataItem(np.arange(10), .5*np.ones(10), pen="grey")
            thresh_it = pg.PlotDataItem(np.arange(10), np.zeros(10), pen="red")

            v.addItem(sig_it)
            v.addItem(thresh_it)
            v.addItem(data_it)
            

            scatter_it = pg.ScatterPlotItem(
                np.arange(10), 
                np.zeros(10), 
                symbol="t", 
                brush=self.raster_colours[-1],
                pen=self.raster_colours[-1],
            )
            v.addItem(scatter_it)
            self.scatter_items[-1] = scatter_it
            v.showAxis("left")
            v.showAxis("left", "bottom")
            v.setXRange(self.dx, 0)
            v.setYRange(-self.y_lim, self.y_lim)
            self.plt_items[-1] = data_it
            self.plt_items_sig[-1] = sig_it
            self.plt_thresh_line[-1] = thresh_it

            v.getViewBox().setMouseEnabled(x=1, y=None)
            self.view_list[-1] = v

            for r in range(rows):
                for c in range(cols):
                    if r * cols + c == self.plot_num - 1:
                        break
                    v = self.canvas.addPlot(row=r, col=c)
                    data_it = pg.PlotDataItem(np.arange(10), np.ones(10))
                    sig_it = pg.PlotDataItem(np.arange(10), .5*np.ones(10), pen="grey")
                    thresh_it = pg.PlotDataItem(np.arange(10), np.zeros(10), pen="red")

                    v.addItem(sig_it)
                    v.addItem(thresh_it)
                    v.addItem(data_it)

                    scatter_it = pg.ScatterPlotItem(
                        np.arange(10), 
                        np.zeros(10), 
                        symbol="t", 
                        brush=self.raster_colours[c],
                        pen=self.raster_colours[c]
                    )

                    v.addItem(scatter_it)
                    self.scatter_items[r * cols + c] = scatter_it
                    if r == rows - 1:
                        v.showAxis("bottom")
                    else:
                        v.hideAxis("bottom")
                    v.showAxis("left")
                    self.plt_thresh_line[r * cols + c] = thresh_it
                    self.plt_items[r * cols + c] = data_it
                    self.plt_items_sig[r * cols + c] = sig_it

                    v.setXLink(self.view_list[-1])
                    v.setYLink(self.view_list[-1])
                    self.view_list[r * cols + c] = v
        else:
            rows = 0

        # spike wavelet plots
        if DO_PLOT_SPIKE_WAVELETS:
            for r in range(rows):
                for c in range(cols):
                    if r * cols + c == self.plot_num:
                        break
                    v = self.shape_canvas.addPlot(row=r, col=c)
                    for i in range(SPIKE_WAVELET_NUM):
                        data_it = pg.PlotDataItem(np.arange(10), np.zeros(10))
                        v.addItem(data_it)
                        self.spike_wavelet_plt_items[r * cols + c].append(data_it)
                    v.showAxis("left")

                    if c > 0 or r > 0:
                        v.setXLink(self.spike_view_list[0])
                        v.setYLink(self.spike_view_list[0])
                    else:
                        v.setXRange(0, self.x_spike_wavelet[-1])
                        v.setYRange(-self.wave_y_lim, self.wave_y_lim)                
                    v.showAxis("bottom")

                    self.spike_view_list[r * cols + c] = v


        r += 1

        # raster plot
        v = self.raster_canvas.addPlot(row=r, col=0, colspan=2) # rowspan=rows + 1, col=max(cols, STATUS_LEN)
        scatter_it = pg.ScatterPlotItem(
            np.arange(10),
            np.zeros(10),
            symbol="o",
            brush=self.raster_colours[0],
            pen=self.raster_colours[0],
        )
        v.addItem(scatter_it)

        data_it = pg.PlotDataItem(
            [0, 0], [-5, self.raster_ylim + 5], pen=[128, 128, 128]
        )
        v.addItem(data_it)

        v.showAxis("bottom")
        v.showAxis("left")
        v.setYRange(0, self.raster_ylim)
        v.setXRange(-10, self.raster_xlim)
        self.raster_plot_view = v
        self.raster_plot_it = scatter_it

    def createStatusPlots(self):
        """"add status bplots to new tab"""
        self.status_plt_items = [None for _ in range(STATUS_LEN)]
        self.status_view_list = [None for _ in range(STATUS_LEN)]

        # Status plots
        for c in range(STATUS_LEN):
            v = self.status_canvas.addPlot(row=0, col=c)
            data_it = pg.PlotDataItem(np.arange(10), np.zeros(10))
            v.addItem(data_it)
            v.showAxis("left")
            self.status_plt_items[c] = data_it

            if c == 0:
                v.setXRange(self.dx, 0)
            #     v.enableAutoRange(axis=pg.ViewBox.YAxis)
            else:
                v.setXLink(self.status_view_list[0])
            v.showAxis("bottom")
            # if c == 0:
            #     v.enableAutoRange(axis=pg.ViewBox.YAxis)
            # else:
            v.setYRange(STATUS_Y_LIMITS[c][0], STATUS_Y_LIMITS[c][1])

            self.status_view_list[c] = v

    def createEnvPlots(self):
        """"add temperature, humidity, co2 and medium volume plots to new tab"""
        it_nums = [5, 4, 1, 1, 4]
        self.lvl_scatter_items = []
        self.temp_scatter_items = []
        self.env_scatter_items = []
        self.noise_scatter_items = []
        self.env_view_list = [None for _ in range(5)]

        # Env plots
        for c, num in enumerate(it_nums):
            if c < 4:
                v = self.env_canvas.addPlot(row=c//2, col=c%2, colspan=1)
            else:
                v = self.env_canvas.addPlot(row=c//2, col=c%2, colspan=2)

            for i in range(num):
                scatter_it = pg.ScatterPlotItem()
                v.addItem(scatter_it)
                if c == 1:
                    self.lvl_scatter_items.append(scatter_it)
                    v.setYRange(-5, 6005) # v.enableAutoRange(axis=pg.ViewBox.YAxis)
                elif c == 0:
                    self.temp_scatter_items.append(scatter_it)
                    v.setYRange(20, 42)
                elif c > 1 and c < 4:
                    self.env_scatter_items.append(scatter_it)
                    if c == 2:
                        v.setYRange(0, 100)
                    else:
                        v.setYRange(0, 8)
                else:
                    self.noise_scatter_items.append(scatter_it)

            v.showAxis("left")
            if c == 0:
                # v.setXRange(self.dt_env, 0)
                v.enableAutoRange(axis=pg.ViewBox.XAxis)
            elif c < 4:
                v.setXLink(self.env_view_list[0])            
            else: 
                v.setYRange(0, 60)
                v.setXRange(0, SHARED_NOISE_MAX)
            v.showAxis("bottom")

            self.env_view_list[c] = v

    def onClickedRadioRasterEl(self):
        """Radio button to change trigger electrode for raster plot"""
        radioButton = self.sender()
        self.raster_trigger_el = radioButton.state
        self.clear_raster = True
        print("Updated Raster Trigger Electrode")

    def onClickedRadioMEA(self):
        """Radio button to change mea for plot with stream from channels"""
        radioButton = self.sender()
        self.mea_state = radioButton.state
        # print(f"Selected Plot channels of MEA {radioButton.state}")
        self.updatePlotChannels()

    def onClickedRadioNet(self):
        """Radio button to change network for plot with stream from channels"""
        radioButton = self.sender()
        self.network_state = radioButton.net_state
        # print(f"Selected Plot channels of Network {radioButton.net_state}")
        self.updatePlotChannels()

    def updatePlotChannels(self):
        """Update the internal channel variable when they have been changed through the radio buttons"""
        network_to_plot = self.network_state + self.mea_state * 15
        # print(f"Plotting network ID {network_to_plot}")
        if PLOT_NETWORKS:
            new_channel_ids = ELECTRODE_MAPPING.mea2recv(
                ELECTRODE_MAPPING.network2mea(
                    np.array([[network_to_plot, el] for el in np.arange(MEA_NUM)])
                )
            )
        else:
            new_channel_ids = ELECTRODE_MAPPING.mea2recv(
                np.arange(ELECTRODE_MAPPING.elec)
                + self.mea_state * ELECTRODE_MAPPING.elec
            )
        self.update_th.ch_num = new_channel_ids
        if DO_PLOT_SPIKE_WAVELETS:
            self.update_th_wavelet.ch_num = new_channel_ids
        self.shared_plot_network.value = network_to_plot
        self.clear_raster = True

        print(
            f"Now plotting {ELECTRODE_MAPPING.recv2mea(new_channel_ids)}") # from recv position {new_channel_ids}"
        # {ELECTRODE_MAPPING.recv2mea(new_channel_ids)}") # which is network electrodes {ELECTRODE_MAPPING.mea2network(ELECTRODE_MAPPING.recv2mea(new_channel_ids))}")

    def onClickedCBVoltage(self):
        cb = self.sender()
        self.update_th.plot_voltage_bool = cb.isChecked()
        self.plot_voltage_bool_gui = cb.isChecked()

    def onClickedCBUpdate(self):
        cb = self.sender()
        self.update_thresh_bool.value = cb.isChecked()
        
    def createEnvInfo(self):
        groupBox = QtWidgets.QGroupBox("")
        vbox = QHBoxLayout()
        self.temperature_text = QtWidgets.QLabel()
        self.temperature_text.setText(
            f"MEA Temperatures in °C: {0:.2f} | {0:.2f} | {0:.2f} | {0:.2f}"
        )
        vbox.addWidget(self.temperature_text)
        vbox.addStretch(1)

        groupBox.setLayout(vbox)
        return groupBox

    def createMeaInfo(self):
        groupBox = QtWidgets.QGroupBox("")
        vbox = QHBoxLayout()        
        self.med_level_text = QtWidgets.QLabel()
        self.med_level_text.setText(f"Medium level: 0 (0) | 0 (0) | 0 (0) | 0 (0)")
        vbox.addWidget(self.med_level_text)
        vbox.addStretch(1)

        groupBox.setLayout(vbox)
        return groupBox
    
    def createRadioGroup(self, cb=True):
        groupBox = QtWidgets.QGroupBox("Select MEA for plotting")
        vbox = QHBoxLayout()

        radio1 = QtWidgets.QRadioButton("0")
        radio1.state = 0
        radio1.toggled.connect(self.onClickedRadioMEA)
        radio1.setChecked(True)
        vbox.addWidget(radio1)

        if MEA_NUM > 1:
            radio2 = QtWidgets.QRadioButton("1")
            radio2.state = 1
            radio2.toggled.connect(self.onClickedRadioMEA)
            vbox.addWidget(radio2)
        if MEA_NUM > 2:
            radio3 = QtWidgets.QRadioButton("2")
            radio3.state = 2
            radio3.toggled.connect(self.onClickedRadioMEA)
            vbox.addWidget(radio3)
        if MEA_NUM > 3:
            radio4 = QtWidgets.QRadioButton("3")
            radio4.state = 3
            radio4.toggled.connect(self.onClickedRadioMEA)
            vbox.addWidget(radio4)

        if cb:
            check1 = QtWidgets.QCheckBox("Trigger signal")
            check1.stateChanged.connect(self.onClickedCBVoltage)
            check1.setChecked(False)

            check2 = QtWidgets.QCheckBox("Update spike threshold")
            check2.stateChanged.connect(self.onClickedCBUpdate)
            check2.setChecked(True)

        vbox.addStretch(1)
        if cb:
            vbox.addWidget(check1)
            vbox.addWidget(check2)

        groupBox.setLayout(vbox)

        return groupBox

    def createRadioGroupNet(self):

        vbox = QHBoxLayout()

        if PLOT_NETWORKS:
            groupBox = QtWidgets.QGroupBox("Select Network for plotting")
            radio_networks = []
            for network_id in range(15):
                radio = QtWidgets.QRadioButton(f".{network_id}")
                radio.net_state = network_id
                radio.toggled.connect(self.onClickedRadioNet)
                radio_networks.append(radio)
            radio_networks[0].setChecked(True)

            for r in radio_networks:
                vbox.addWidget(r)
        else:
            groupBox = QtWidgets.QGroupBox()
        vbox.addStretch(1)
        
        groupBox.setLayout(vbox)
        return groupBox

    def createSTTRPGroup(self):
        groupBox = QtWidgets.QGroupBox("Select STTRP trigger")

        radio_el1 = QtWidgets.QRadioButton("0")
        radio_el1.state = 0
        radio_el1.toggled.connect(self.onClickedRadioRasterEl)

        radio_el2 = QtWidgets.QRadioButton("1")
        radio_el2.state = 1
        radio_el2.toggled.connect(self.onClickedRadioRasterEl)

        radio_el3 = QtWidgets.QRadioButton("2")
        radio_el3.state = 2
        radio_el3.toggled.connect(self.onClickedRadioRasterEl)

        radio_el4 = QtWidgets.QRadioButton("3")
        radio_el4.state = 3
        radio_el4.toggled.connect(self.onClickedRadioRasterEl)

        radio_el1.setChecked(True)
        vbox = QHBoxLayout()
        vbox.addWidget(radio_el1)
        vbox.addWidget(radio_el2)
        vbox.addWidget(radio_el3)
        vbox.addWidget(radio_el4)
        vbox.addStretch(1)
        groupBox.setLayout(vbox)
        return groupBox

    # from here on the update callbacks follow which are fed by the threads in plot_stream.py
    @QtCore.pyqtSlot(tuple)
    def update_data_osc(self, data):
        """Update data in mea plot when emitted from respective update thread, callback"""
        if len(data) > 1:
        # use emitted data
        
            for i in range(self.plot_num):
                self.plt_items[i].setData(self.x_voltage, data[1][i])
                if len(data) > 2:
                    self.plt_items_sig[i].setData(self.x_voltage, data[-2][i])
                    th_plot = data[-1][i]
                    self.plt_thresh_line[i].setData(
                        self.x_voltage[[0, -1]], [th_plot, th_plot]
                    )
                else:
                    self.plt_items_sig[i].setData()
                    self.plt_thresh_line[i].setData()
            
            for it in self.scatter_items:
                it.setData()

            # scatter spikes
            if len(data[0]):
                pkg_shifts = []
                plt_id_prev = data[0][0][0]

                for plt_id, pkg_shift in data[0]:
                    # add detect duration because of backwards array readout
                    pkg_shift = (pkg_shift + 2*DETECT_DURATION) % PLOT_BUF_LEN
                    if plt_id == plt_id_prev:
                        # if spike on same channel as last one append spike
                        pkg_shifts.append(pkg_shift)
                    else:
                        # if spikes on new channel plot previous channel

                        self.scatter_items[plt_id_prev].setData(
                            -np.array(pkg_shifts) / FS * 1000,
                            np.zeros(len(pkg_shifts)),
                            symbol="t",
                            brush=self.raster_colours[plt_id_prev],
                            pen=self.raster_colours[plt_id_prev],
                        )
                        pkg_shifts = [pkg_shift]
                    plt_id_prev = plt_id

                self.scatter_items[plt_id].setData(
                    -np.array(pkg_shifts) / FS * 1000,
                    np.zeros(len(pkg_shifts)),
                    symbol="t",
                    brush=self.raster_colours[plt_id],
                    pen=self.raster_colours[plt_id],
                )

        if len(data) == 1:
            for i in range(STATUS_LEN):
                self.status_plt_items[i].setData(
                    self.x_voltage, data[0][i].astype(np.float32)
                )

    @QtCore.pyqtSlot(tuple)
    def update_raster(self, data):
        """Update data in raster plot when emitted from respective update thread, callback"""
        if self.clear_raster:
            self.raster_plot_it.setData()
            self.clear_raster = False
        if len(data) == 3: # this is the stimulated data
            index_rec, raster_spike_vec, stim = data
            index_time = index_rec*STIMULUS_CYCLE/FS
            if index_rec < self.raster_last_index:
                self.raster_plot_it.setData()
            for el, spikes in enumerate(raster_spike_vec):
                if len(spikes):
                    self.raster_plot_it.addPoints(
                        spikes,
                        np.full(len(spikes), index_time),
                        symbol="o",
                        brush=self.raster_colours[el],
                        pen=self.raster_colours[el],
                        size=1,
                        pxMode=True,
                    )

            for delay, _, el in stim:
                self.raster_plot_it.addPoints(
                    [-delay/FS*1e3],
                    [index_time],
                    symbol="x",
                    brush=self.raster_colours[el],
                    pen=self.raster_colours[el],
                    size=1,
                    pxMode=True,
                )
        if index_time < self.raster_last_index:
            self.clear_raster = True
        self.raster_last_index = index_time


    @QtCore.pyqtSlot(tuple)
    def update_temp(self, data):
        """Update data in temperature and environment plot when emitted from respective update thread, callback"""
        mean_temp, mean_hum, mean_co2, med_level, med_counter, shared_noise = data
        self.temperature_text.setText(
            f"T [°C]: {mean_temp[-1]:.2f} | CO2 [%]: {mean_co2:.2f} | H [%]: {mean_hum:.2f} \nMEA T [°C]: {mean_temp[0]:.2f} | {mean_temp[1]:.2f} | {mean_temp[2]:.2f} | {mean_temp[3]:.2f}"
        )
        self.med_level_text.setText(
            f"Medium level: {med_level[0]} ({med_counter[0]}) | {med_level[1]} ({med_counter[1]}) | {med_level[2]} ({med_counter[2]}) | {med_level[3]} ({med_counter[3]})"
        )

        current_time = datetime.now().timestamp()
        self.last_plotted_time[1] = current_time
        rel_time = current_time-self.last_plotted_time[0]

        for plot_id, lvl_data in enumerate(med_level):
            self.lvl_scatter_items[plot_id].addPoints(
                [rel_time],
                [lvl_data],
                symbol="o",
                brush=self.env_colours[plot_id],
                pen=self.env_colours[plot_id],
                size=6,
                pxMode=True,
            )

        for plot_id, temp_data in enumerate(mean_temp):
            self.temp_scatter_items[plot_id].addPoints(
                [rel_time],
                [temp_data],
                symbol="o",
                brush=self.env_colours[plot_id],
                pen=self.env_colours[plot_id],
                size=6,
                pxMode=True,
            )

        for plot_id, env_data in enumerate([mean_hum, mean_co2]):
            self.env_scatter_items[plot_id].addPoints(
                [rel_time],
                [env_data],
                symbol="o",
                brush=self.env_colours[-1],
                pen=self.env_colours[-1],
                size=6,
                pxMode=True,
            )

        noise_bins = (np.arange(SHARED_NOISE_BINS)+.35)/SHARED_NOISE_BINS*SHARED_NOISE_MAX
        for plot_id, sct in enumerate(self.noise_scatter_items):
            sct.setData(
                noise_bins+plot_id*0.1*SHARED_NOISE_MAX/SHARED_NOISE_BINS,
                shared_noise[plot_id*SHARED_NOISE_BINS:(plot_id+1)*SHARED_NOISE_BINS],
                symbol="t",
                brush=self.env_colours[plot_id],
                pen=self.env_colours[plot_id],
                size=6,
                pxMode=True,
            )        

        if rel_time > self.dt_env:
            for it in self.env_scatter_items:
                it.clear()
            for it in self.lvl_scatter_items:
                it.clear()
            for it in self.temp_scatter_items:
                it.clear()            
            self.last_plotted_time[0] = self.last_plotted_time[1]    

    @QtCore.pyqtSlot(tuple)
    def update_wavelet(self, data):
        """Update data in spike shapes plot when emitted from respective update thread, callback"""
        spike_wavelets = data[0] 
        for plot_id, wavelet_list in enumerate(spike_wavelets):
            for data_id, wavelet in enumerate(wavelet_list):
                self.spike_wavelet_plt_items[plot_id][data_id].setData(self.x_spike_wavelet, wavelet)
