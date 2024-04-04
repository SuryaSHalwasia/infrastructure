import requests
import json 
import time
import sys
import os

scripts_dir = os.path.dirname(os.path.abspath(__file__))
csv_module_path = os.path.join(scripts_dir,'csv')

if csv_module_path not in sys.path:
    sys.path.append(csv_module_path)

import pothole_csv

directory = os.getcwd()
# Specify the file name
filename = "csv\\Files\\pothole.csv"

csv_file_path = os.path.join(directory, filename)

def make_http_request(url, method='GET', headers=None, body=None, verify=False):
    try:
        # Construct the request
        if method.upper() == 'GET':
            response = requests.get(url, headers=headers)
        elif method.upper() == 'POST':
            response = requests.post(url, headers=headers, data=body, verify=verify)
        else:
            print(f"Unsupported HTTP method: {method}")
            return None

        # Print the response
        print(f"Response Code: {response.status_code}")
        
        print("\n\n")

        return response

    except Exception as e:
        print(f"Error making HTTP request: {e}")
        return None

# Example usage:
if __name__ == "__main__":
    frequency = input("Enter the wait time in seconds: ")

    while(True):
        base_url = "http://localhost:8051/"
        url = base_url + "connections"
        

        method = 'GET'
          # Replace 'your-api-key' with your actual API key

        response = make_http_request(url, method)

        if response and response.status_code == 200:
            try:
                # Parse the JSON response from response.text
                response_json = response.json()

                # Extract the connection_id values as a list
                completed_connections = [entry["connection_id"] for entry in response_json.get("results", []) if entry.get("rfc23_state") == "completed"]

                content = pothole_csv.parse_gps_data(csv_file_path)
                print("Sending message " + str(content[0][0]) + "," + str(content[0][1]))
                body_dict = {"content": content}
                body = json.dumps(body_dict)
                method = 'POST'
                # Print the result
                for connection in completed_connections:
                    url = base_url + "connections/" + connection + "/send-message"
                    response_post = make_http_request(url, method, body=body)
                    print(response_post.status_code)
                    print(response_post.text)
                    if(response_post.status_code != 200):
                        raise Exception("Unable to send message to connection " + connection)


            except json.JSONDecodeError as e:
                print(f"Error decoding JSON: {e}")
        
        time.sleep(int(frequency))