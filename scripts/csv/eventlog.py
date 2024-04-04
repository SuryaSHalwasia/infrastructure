import csv
import os

# Specify the directory where the CSV file is located
directory = os.getcwd()
# Specify the file name
filename = "\\csv\\Files\\eventlog.csv"


# Construct the full path to the CSV file
csv_file_path = os.path.abspath(directory + filename)

# Initialize an empty dictionary to store dictionaries
data = {}

# Open the CSV file using a context manager to ensure it's properly closed after reading
with open(csv_file_path, "r") as csv_file:
    # Create a CSV reader object that directly reads rows as dictionaries
    csv_reader = csv.reader(csv_file)
    
    # Extract the header row
    header = next(csv_reader)
    
    # Iterate over each row in the CSV file
    for row in csv_reader:
        try:
            # Extract values from the row
            event, gps_str, speed, timestamp = row
            
            # Parse GPS coordinates
            gps = eval(gps_str)
            
            # Store the data in the dictionary
            data[tuple(gps)] = {'event': event, 'speed': float(speed)}
        except ValueError as e:
            print(f"Skipping row: {row}. Reason: {e}")

# Example: Retrieve event and speed for a specific GPS location
'''gps_location = (40.36043581976105, -74.59656142995496)  # Example GPS coordinates
if gps_location in data:
    event = data[gps_location]['event']
    speed = data[gps_location]['speed']
    print("Event:", event)
    print("Speed:", speed)
else:
    print("Data not available for the specified GPS location.")
'''