import numpy as np

def check_action(action,dim):
    null_action = np.zeros(dim,dtype=float)-1
    message     = "none"
    if not isinstance(action,np.ndarray):
        message = "Action is not a numpy array. Action was not used."
        action  = null_action
    elif action.ndim != 1:
        message = f"Action has wrong dimension. is: {action.shape}, ought: {null_action.shape}. Action was not used."
        action  = null_action
    elif action.size != dim:
        message = f"Action has wrong dimension. is: {action.shape}, ought: {null_action.shape}. Action was not used."
        action  = null_action
    # elif not np.issubdtype(action.dtype,np.float32):
    #     message = "Action needs to be of type float. Action was not used."
    #     action  = null_action
    elif not np.all((action >= -1) & (action <= 1)):
        message = "Each of your elements in action needs to be in [-1,1]. At least one of your action elements is out of range. Action was not used."
        action  = null_action
    return action,message
