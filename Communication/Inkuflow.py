from ControlPort import ControlPort
import time
import numpy as np
import datetime
PUMP_STEPS_FOR_100uL = 9257
class Inkuflow:
    """Class to control inkulevel and inkube pump with valves for multplexing"""
    # stepper motor steps that correspond to pumped volume of 100 ul
    pump_steps_for_100uL = PUMP_STEPS_FOR_100uL

    def __init__(
        self,
        ctrl: ControlPort,
        active_mea=[1, 1, 1, 1], 
        medium_lvl_lim_min=np.array([2800, 2800, 2800, 2800]),
        medium_lvl_lim_max=np.array([70_000, 70_000, 70_000, 70_000]),
        pump_amount_for_const=PUMP_STEPS_FOR_100uL/10,  # roughly 10 ul
        pump_range_lim=[5_000, 60_000],
        reservoir_valves=np.array([4, 5]).reshape(1, 2),  # in, out
        mea_valves=np.array([0, 1, 2, 3]).reshape(1, 4),
    ):
        """
        Initializes an instance of the Inkuflow class.
        Args:
            ctrl (ControlPort): The control port object.
            active_mea (list, optional): List of active MEAs. Inkulevels are A B C D, make entry 1 to activate control (one hot encoding). Defaults to [1, 1, 1, 1].
            medium_lvl_lim_min (np.array, optional): Array of minimum medium level limits. Defaults to np.array([2800, 2800, 2800, 2800]).
            medium_lvl_lim_max (np.array, optional): Array of maximum medium level limits. Defaults to np.array([70000, 70000, 70000, 70000]).
            pump_amount_for_const (int, optional): Pump amount for constant level. Defaults to 1000.
            pump_range_lim (list, optional): stepper motor limits for the pump. Defaults to [5000, 60000].
            reservoir_valves (np.array, optional): Array of reservoir valves. Put the IDs of the driver channels here. Defaults to np.array([4, 5]).reshape(1, 2).
            mea_valves (np.array, optional): Array of MEA valves. Defaults to np.array([0, 1, 2, 3]).reshape(1, 4).
        """
        self.ctrl = ctrl
        self.active_mea = np.array(active_mea)

        self.medium_lvl_lim_min = medium_lvl_lim_min
        self.medium_lvl_lim_max = medium_lvl_lim_max

        self.pump_amount_for_const = pump_amount_for_const
        self.pump_range_lim = pump_range_lim

        self.num_liquids = mea_valves.shape[0]
        self.mea_valves = mea_valves
        self.reservoir_valves = reservoir_valves
        if self.num_liquids != reservoir_valves.shape[0]:
            print(f"Error: Wrong dimensions for valve matrix!")

    def measure_lvl(self, iterations, key='median'):
        """
        Measures the inkulevel.
        Args:
            iterations (int): repeat the measurement this often.
            key (str, optional): The key how to process the multiple measurements. Choose between median, mean, min and max. Defaults to 'median'.
        Returns:
            np.array: The measured inkulevel.
        """
        # fill the array with measurements, 10 measurements are received per iteration
        lvl_data = np.zeros((iterations * 10, 4))
        counter_time = np.zeros((2, 5))
        for it in range(iterations):
            r_chunk = self.ctrl.get_level()
            for step, r in enumerate(r_chunk):
                lvl_data[it * 10 + step] = r[1:5]
            if not it:
                counter_time[0, 0] = r_chunk[0, 0]
                counter_time[0, 1:] = r_chunk[0, 5:]
            if it == iterations - 1:
                counter_time[1, 0] = r_chunk[-1, 0]
                counter_time[1, 1:] = r_chunk[-1, 5:]

        # process the measurement
        if key == 'mean':
            lvl_mat = np.mean(np.array(lvl_data), axis=0)  # switched to median
        elif key == 'median':
            lvl_mat = np.median(np.array(lvl_data), axis=0)
        elif key == 'max':
            lvl_mat = np.max(np.array(lvl_data), axis=0)
        elif key == 'min':
            lvl_mat = np.min(np.array(lvl_data), axis=0)
        else:
            lvl_mat = np.squeeze(np.array(lvl_data)[0,:])

        # Log the command with a timestamp
        if self.ctrl.do_log:            
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'MEASURED PARAMETER medium_level at VALUE {lvl_mat}'
            self.ctrl.logger.info(f'{timestamp} - {log_entry}')
        return lvl_mat

    def const_level(
            self, 
            duration_in_s, 
            iterations=5, 
            liquid=0, 
            target_lvl=None, 
        ):
        """
        Maintains a constant level by measuring the volume and pumping in stepwise once below a certain threshold.
        Args:
            duration_in_s (int): The duration in seconds to do this operation.
            iterations (int, optional): The number of iterations for the feedback measurement (self.measure_lvl). Defaults to 5.
            liquid (int, optional): The liquid ID to refill the MEA. Defaults to 0.
            target_lvl (np.array, optional): The target level below which the pumping starts. Defaults to None.
        """
        if target_lvl is None:
            target_lvl = self.medium_lvl_lim_min
        start_t = time.time()
        while((time.time()-start_t) < duration_in_s):
            self.pump_until_target(
                measurement_iterations=iterations, 
                liquid=liquid, 
                target_lvl=target_lvl, 
                pump_step_size=self.pump_amount_for_const, 
            )

    def pump_until_target(
        self,
        measurement_iterations=1,
        liquid=0,
        target_lvl=np.array([3_000, 3_000, 3_000, 3_000]),
        direction=-1,
        pump_step_size=100,
        min_max_steps=[0, 20],
        init_measurement=None,
        wait_time_before_measure=0,
    ):
        """
        Pumps until the target level is reached.
        Args:
            measurement_iterations (int, optional): The number of measurement iterations. Defaults to 1.
            liquid (int, optional): The liquid ID. Defaults to 0.
            target_lvl (np.array, optional): The target level. Defaults to np.array([3000, 3000, 3000, 3000]).
            direction (int, optional): The direction of pumping. Defaults to -1 which is pumping in, 1 is retrieving liquid.
            pump_step_size (int, optional): The pump step size after which the measurement starts again. Defaults to 100.
            min_max_steps (list, optional): The minimum and maximum steps that can be executed once registered outside the threshold but not reaching it. Defaults to [0, 20].
            init_measurement (np.array, optional): The initial measurement. Defaults to None.
            wait_time_before_measure (int, optional): The wait time before measurement. Defaults to 0.
        """
        steps = 0

        while steps < min_max_steps[1]:
            # measure the level
            if init_measurement is None:
                if steps:
                    time.sleep(wait_time_before_measure)
                lvl_mat = self.measure_lvl(measurement_iterations, key='median')
            else:
                lvl_mat = init_measurement
                init_measurement = None

            # determine which MEAs are below threshold and active
            if steps < min_max_steps[0]:
                pump_in_mea = np.where(self.active_mea)[0]
            else:
                pump_in_mea = np.where(lvl_mat*-1*direction < target_lvl*-1*direction)[0]
            print(f'Pump MEA is {pump_in_mea}')
            switch_vector = np.atleast_1d(np.array(
                [self.mea_valves[liquid, id] for id in pump_in_mea if self.active_mea[id]]
            ).squeeze())

            # pump a step
            if switch_vector.shape[0]:
                start_t = time.time()

                self.pump_amount(switch_vector, direction, pump_step_size, liquid)
                steps += 1
            else: 
                break
            print(f'end, start measuring again after {time.time()-start_t}')

    def pump_until_single_open(
        self, 
        measurement_iterations=1,
        liquid=0, # liquid id
        target_lvl=3_000, # set point for level, 100 lvl units correspond to 10 ul
        target_mea=0,
        direction=-1, # -1 is in MEA
        anticipated_step_size=5_000, # 
        anticipated_dist = 1_000, 
        max_factor=1.5,  
        init_measurement=None,
        wait_time_before_measure=0, # in seconds after pumping before measure
        approach_factor = .9, 
        max_iterations = 5, 
        discard_measurements = 2, 
        min_step_size = 500, 
        adapt_step_size = False, # if False use calibration
    ):

        """
        Pumps until threshold is hit with a single valve open.
        Args:
            measurement_iterations (int, optional): The number of measurement iterations. Defaults to 1.
            liquid (int, optional): The liquid ID. Defaults to 0.
            target_lvl (int, optional): The target level. Defaults to 3000.
            target_mea (int, optional): The target MEA. 0 is for MEA A, 1 for MEA B and so on. Defaults to 0.
            direction (int, optional): The direction of pumping (1 is retrieve from MEA, -1 is in to MEA). Defaults to -1.
            anticipated_step_size (int, optional): Pumping steps that should result in the volume difference from calibration. Defaults to 5000.
            anticipated_dist (int, optional): Level value distance between calibration values which are assumed to represent the volume difference. Defaults to 1000.
            max_factor (float, optional): safety threshold, maximally this times anticipated step size is pumped in total. Defaults to 1.5.
            init_measurement (np.array, optional): The initial measurement. Defaults to None.
            wait_time_before_measure (int, optional): The wait time before measurement of level after pumping in sec. Defaults to 0.
            approach_factor (float, optional): The approach factor with which calcuzlated pumping is multiplied. Defaults to 0.9.
            max_iterations (int, optional): The maximum number of iterations that the target is tried to reach. Defaults to 5.
            discard_measurements (int, optional): The number of level measurements after pumping to discard. Defaults to 2.
            min_step_size (int, optional): The minimum step size of a single step. Defaults to 500.
            adapt_step_size (bool, optional): Whether to adapt the step size according to the last step. Defaults to False.
        """
        valve = self.mea_valves[liquid, target_mea]

        self.ctrl.switch_valve(self.reservoir_valves[liquid, :].flatten(), [0], 9)
        res_valves_not_pumped = np.array([self.reservoir_valves[l, :].flatten() for l in range(self.num_liquids) if l != liquid]).flatten()
        self.ctrl.switch_valve(res_valves_not_pumped, [1]*res_valves_not_pumped.shape[0], 9)
        mid_position = self.pump_range_lim[0]+.5*(self.pump_range_lim[1]-self.pump_range_lim[0])
        self.ctrl.send_commands()

        # check pump position and refill if too little fluid in liquid
        if direction == -1:
            if (
                self.ctrl.pump_position
                < anticipated_step_size*max_factor + self.pump_range_lim[0]
            ):
                # open the reservoir
                self.ctrl.switch_valve(self.reservoir_valves[liquid, :].flatten(), [1], self.ctrl.open_delay)
                self.ctrl.send_commands()

                # refill the syringe
                self.ctrl.pump_abs(mid_position, self.ctrl.pump_delay) 
                self.ctrl.send_commands()
                time.sleep(self.ctrl.pump_wait_per_step*60_000)

                # close the reservoir
                time.sleep(self.ctrl.retrieve_wait)
                self.ctrl.switch_valve(self.reservoir_valves[liquid, :].flatten(), [0], self.ctrl.refill_delay)
                self.ctrl.send_commands()
                time.sleep(15)
        else:
            if (
                self.ctrl.pump_position
                > self.pump_range_lim[-1] - anticipated_step_size*max_factor
            ):
                # open the reservoir
                self.ctrl.switch_valve(self.reservoir_valves[liquid, :].flatten(), [1], self.ctrl.open_delay)
                self.ctrl.send_commands()

                # refill the syringe
                self.ctrl.pump_abs(mid_position, self.ctrl.pump_delay)
                self.ctrl.send_commands()
                time.sleep(self.ctrl.pump_wait_per_step*60_000)

                # close the reservoir
                self.ctrl.switch_valve(self.reservoir_valves[liquid, :].flatten(), [0], self.ctrl.refill_delay)
                self.ctrl.send_commands()
                time.sleep(15)

        # open the MEA valve
        self.ctrl.switch_valve(valve, 1, self.ctrl.open_delay)
        self.ctrl.send_commands()

        # start the pumping
        iterations = 0
        pumped_steps = 0
        missing_steps = 0
        dist = 0
        pump_amount_steps = 0
        step_factor = anticipated_step_size/anticipated_dist # factor translates bit inkulevel difference to pump steps
        # start pumping with measurement feedback
        while pumped_steps < anticipated_step_size*max_factor and iterations < max_iterations:

            # measure inkulevel
            if init_measurement is None:
                if iterations:
                    time.sleep(wait_time_before_measure)
                    self.measure_lvl(discard_measurements, key='median') # discard stored measurement                
                lvl_mat = self.measure_lvl(measurement_iterations, key='mean')
            else:
                lvl_mat = init_measurement
                init_measurement = None

            # compute distance to target
            dist = target_lvl - lvl_mat[target_mea]
            if adapt_step_size:
                if not iterations: # initially take the value known from calibration
                    init_dist = dist
                else: # afterwards use the now measured one
                    step_factor = pumped_steps/(init_dist-dist)
            # if done with pumping break
            if dist*direction > 0:
                print(f'Target MEA: target reached with {dist} {target_lvl} and {lvl_mat[target_mea]}')
                break

            # move the pump to pump liquid
            missing_steps = dist*step_factor
            pump_amount_steps = abs(int(approach_factor*missing_steps+.5))
            print(f'Target MEA {target_mea}: still missing {dist} - should correspond to {missing_steps} steps and leads to {pump_amount_steps}')

            pump_amount_steps = min(pump_amount_steps, max_factor*anticipated_step_size - pumped_steps)
            pump_amount_steps = max(min_step_size, pump_amount_steps)

            pumped_steps += pump_amount_steps
            print(f'Target MEA {target_mea}: pumped {pumped_steps} of max {anticipated_step_size*max_factor} and missing {missing_steps}')

            self.ctrl.pump_rel(direction * pump_amount_steps, self.ctrl.pump_delay)
            self.ctrl.send_commands()
            time.sleep(self.ctrl.pump_wait_per_step*pump_amount_steps)

            iterations += 1

        # switch back
        time.sleep(self.ctrl.wait_mea_close)
        self.ctrl.switch_valve(valve, 0, self.ctrl.close_delay)
        self.ctrl.send_commands()                

        # Log the command with a timestamp
        if self.ctrl.do_log:            
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'EXECUTED COMMAND pump_until_single with liquid {liquid}, direction {direction}, steps {pump_amount_steps} for MEAs {target_mea}'
            self.ctrl.logger.info(f'{timestamp} - {log_entry}')
            
        self.switch_reservoir(0, 10) # after close delay of mea so can be short delay (1 sec)
        time.sleep(5*1) # wait for sum of delays

    def pump_amount(
        self, switch_vector, direction, pump_amount_steps, liquid=0
    ):  # direction out 1, in -1
        """
        Pumps a specific amount by first switching the respective valves and then moving the stepper motor.
        Args:
            switch_vector (np.array): The valves to open.
            direction (int): The direction of pumping. 1 is out of MEA, -1 is in to the MEA.
            pump_amount_steps (int): The pump amount in steps. self.pump_steps_for_100 corresponds to 100 ul.
            liquid (int, optional): The liquid ID. Defaults to 0.
        """
    
        # number of MEAs to pump simultaneously, usually only 1 at a time
        num_of_mea = switch_vector.shape[0]
        
        if num_of_mea:
            # open the reservoir for all liquids that are not pumped and close it for the liquid that is pumped
            self.ctrl.switch_valve(self.reservoir_valves[liquid, :].flatten(), [0], 9)
            res_valves_not_pumped = np.array([self.reservoir_valves[l, :].flatten() for l in range(self.num_liquids) if l != liquid]).flatten()
            self.ctrl.switch_valve(res_valves_not_pumped, [1]*res_valves_not_pumped.shape[0], 9)
            self.ctrl.send_commands()
            for m_valve in switch_vector:
                # check if pump position is in range to pump the liquid, otherwise refill
                if direction == -1:
                    if (
                        self.ctrl.pump_position
                        < pump_amount_steps + self.pump_range_lim[0]
                    ):
                        self.ctrl.switch_valve(self.reservoir_valves[liquid, :].flatten(), [1], self.ctrl.open_delay)
                        self.ctrl.send_commands()

                        self.ctrl.pump_abs(self.pump_range_lim[-1], self.ctrl.pump_delay)
                        self.ctrl.send_commands()
                        time.sleep(self.ctrl.pump_wait_per_step*60_000)
                        time.sleep(self.ctrl.retrieve_wait)

                        self.ctrl.switch_valve(self.reservoir_valves[liquid, :].flatten(), [0], self.ctrl.refill_delay)
                        self.ctrl.send_commands()
                        time.sleep(15)
                else:
                    if (
                        self.ctrl.pump_position
                        > self.pump_range_lim[-1] - pump_amount_steps
                    ):
                        self.ctrl.switch_valve(self.reservoir_valves[liquid, :].flatten(), [1], self.ctrl.open_delay)
                        self.ctrl.send_commands()

                        self.ctrl.pump_abs(self.pump_range_lim[0], self.ctrl.pump_delay)
                        self.ctrl.send_commands()
                        time.sleep(self.ctrl.pump_wait_per_step*60_000)
                        # wait 10 sec
                        self.ctrl.switch_valve(self.reservoir_valves[liquid, :].flatten(), [0], self.ctrl.refill_delay)
                        self.ctrl.send_commands()
                        time.sleep(15)

                # open the MEA valve
                self.ctrl.switch_valve(m_valve, 1, self.ctrl.open_delay)
                self.ctrl.send_commands()

                # pump in
                self.ctrl.pump_rel(direction * pump_amount_steps, self.ctrl.pump_delay)
                self.ctrl.send_commands()
                time.sleep(self.ctrl.pump_wait_per_step*pump_amount_steps)

                # close again
                time.sleep(self.ctrl.wait_mea_close)
                self.ctrl.switch_valve(m_valve, 0, self.ctrl.close_delay)
                self.ctrl.send_commands()                

            # Log the command with a timestamp
            if self.ctrl.do_log:                
                timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                log_entry = f'EXECUTED COMMAND pump_amount with liquid {liquid}, direction {direction}, steps {pump_amount_steps} for MEAs {switch_vector}'
                self.ctrl.logger.info(f'{timestamp} - {log_entry}')
            
            self.switch_reservoir(0, 10) # after close delay of mea so can be short delay (1 sec)
            time.sleep(5*num_of_mea) # wait for sum of delays

    def switch_reservoir(self, state=0, delay=8):
        """
        Switches the reservoir valves to open (1) or closed (0) state.
        Args:
            state (int, optional): The state of the reservoir. Defaults to 0.
            delay (int, optional): The delay. Defaults to 8.
        """
        self.ctrl.switch_valve(
            self.reservoir_valves.flatten(), 
            [state] * self.num_liquids, 
            delay=delay)
        self.ctrl.send_commands()

    def exchange_amount_no_fb(
        self,
        exchange_amount_steps,
        liquids=[0, 1],
        liquid_directions=[-1, 1],
        target_mea=None,
    ):
        """
        Exchanges a specific amount without feedback.
        Args:
            exchange_amount_steps (int): The exchange amount in steps on the pump.
            liquids (list, optional): The list of liquids. Defaults to [0, 1].
            liquid_directions (list, optional): The list of liquid directions. Defaults to [-1, 1].
            target_mea (np.array, optional): The target MEA. Defaults to the class active MEAs. One hot encoding.
        """   
        if target_mea is None:
            target_mea = self.active_mea
        # iterate over liquids and directions
        for l_num in range(len(liquids)):
            # get switch vector for the liquid and mea
            switch_vector = self.mea_valves[liquids[l_num], np.where(target_mea)[0]]
            # execute the pumping
            self.pump_amount(
                switch_vector, liquid_directions[l_num], exchange_amount_steps, liquid=liquids[l_num]
            )

    def exchange_amount_fb(
        self,
        measurement_iterations=1,
        target_mea=None,
        liquid_out=0,
        liquid_in=1,
        pump_amount_steps_out=1_000,
        pump_step_size_in=500, 
    ):
        """
        Exchanges a specific amount with feedback.
        Args:
            measurement_iterations (int, optional): The number of measurement iterations on inkulevel. Defaults to 1.
            target_mea (np.array, optional): The target MEA. One hot. Defaults to None.
            liquid_out (int, optional): The liquid ID for retrieving fluid. Defaults to 0.
            liquid_in (int, optional): The liquid ID for in. Defaults to 1.
            pump_amount_steps_out (int, optional): The pump amount in steps for out. Defaults to 1000.
            pump_step_size_in (int, optional): The pump step size for in. Defaults to 500.
        """
        # measure the volume before
        lvl_mat_before = self.measure_lvl(measurement_iterations)
        if target_mea is None:
            target_mea = self.active_mea
        # retrieve liquid without feedback
        switch_vector = np.atleast_1d(np.array(
            [self.mea_valves[liquid_out, id] for id in np.where(target_mea)]
        ).squeeze())
        print(f'Sw vector: {switch_vector} and shape {switch_vector.shape}')
        self.pump_amount(switch_vector, 1, pump_amount_steps_out, liquid=liquid_out)

        # measure afterwards
        lvl_mat_after = self.measure_lvl(measurement_iterations)
        # get the difference in level values and cehck that the direction matches
        delta_lvl = lvl_mat_after - lvl_mat_before
        print(
            f"Delta level after removing {pump_amount_steps_out} steps: {delta_lvl}, target before is {lvl_mat_before}"
        )

        if np.any(delta_lvl[target_mea] > 0):
            print(f'Error: wrong direction detected')

        # pump in the liquid with feedbacked method
        self.pump_until_target(
            liquid=liquid_in, 
            target_lvl=lvl_mat_before, 
            pump_step_size=pump_step_size_in, 
            init_measurement=lvl_mat_after)

        