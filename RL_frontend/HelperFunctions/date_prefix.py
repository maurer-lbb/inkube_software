from datetime import datetime
def generate_date_prefix():
    """Generate a date prefix in the format YYMMDD_HHMMSS."""
    date_for_prefix = datetime.now().strftime('%Y%m%d')[2:]
    time_for_prefix = datetime.now().strftime('%H%M%S')
    date_prefix = f'{date_for_prefix}_{time_for_prefix}'
    return date_prefix