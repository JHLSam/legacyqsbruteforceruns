import os
import sys
import requests
import time

"""
if do not want to hard code api token or chat id, then refer to username = os.environ.get("USERNAME") comment in line 25, otherwise, just fill in your variables here lines 9,10. How 2 get these 2 variables? Follow instructions in instructions.txt
"""
API_TOKEN = "" #put token
CHAT_ID = "" #put chat id

#use from referenced variable in 1st argument of main method in parent process ./retry.sh line 30
amount = float(sys.argv[1])
print(f"py top_up_amt: {amount}")

status = sys.argv[2]
print(f"py status: {status}")

num_mech_txs = int(sys.argv[3])
print(f"py num_mech_txs: {num_mech_txs}")

service_num = int(sys.argv[4])
print(f"py service_num: {service_num}")

#use from environment variable exported in bash "export USERNAME="bob" but obviously, swap with your required  more sensitive env var such as API KEY or CHATID IF you don't want to hard code it here then replace it in line 45 accordingly
username = os.environ.get("USERNAME")
print(f"Username from env: {username}")

def pub_message(token, chat_id, message):
    url = f'https://api.telegram.org/bot{token}/sendMessage'
    payload = {
        'chat_id': chat_id,
        'text': message
    }

    response = requests.post(url, data=payload)

    if response.status_code == 200:
        print('Message sent successfully!')
    else:
        print('Failed to send message:', response.text)

message = f"service {service_num}: status:{status} | num_mech_txs:{num_mech_txs} | top_up_needed:{amount}"
        
pub_message(API_TOKEN,CHAT_ID,message)



