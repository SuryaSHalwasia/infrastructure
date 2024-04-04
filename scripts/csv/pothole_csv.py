import csv
import os

# Example usage:
# Specify the directory where the CSV file is located
#directory = os.getcwd()
# Specify the file name
#filename = "\\csv\\Files\\pothole.csv"

#csv_file_path = os.path.join(directory, filename)

def parse_gps_data(csv_file):
    gps_data = []

    with open(csv_file, mode='r') as file:
        csv_reader = csv.DictReader(file)
        for row in csv_reader:
            gps_str = row.get('gps', '')
            if gps_str:
                gps_values = gps_str.strip('[]').split(',')
                gps_values = [float(value.strip()) for value in gps_values]
                if len(gps_values) == 2:
                    gps_data.append(gps_values)

    print(gps_data)
    return gps_data


#gps_list = parse_gps_data(csv_file_path)
#print(gps_list)
