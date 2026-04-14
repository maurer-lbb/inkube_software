import numpy as np

def check_action(action,dim):
    null_action = np.zeros(4,dtype=int) # 4, as each electrode gets one stim slot
    message     = "none"
    if not isinstance(action,np.ndarray):
        message = "Action is not a numpy array. Action was not used."
        action  = null_action
    elif action.ndim != 1:
        message = f"Action has wrong dimension. is: {action.shape}, ought: {null_action.shape}. Action was not used."
        action  = null_action
    elif action.size != 4:
        message = f"Action has wrong dimension. is: {action.shape}, ought: {null_action.shape}. Action was not used."
        action  = null_action
    elif not np.issubdtype(action.dtype,np.integer):
        message = "Action needs to be of type integer. Action was not used."
        action  = null_action
    elif not np.all((action >= 0) & (action <= dim)):
        message = f"Each of your elements in action needs to be 0,1,...,{dim}. At least one of your action elements is out of range. Action was not used."
        action  = null_action
    return action,message
