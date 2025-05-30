import os
import re
from collections import defaultdict

def parse_log(logfile):
    # Check if the log file exists
    if not os.path.isfile(logfile):
        print(f"Log file not found: {logfile}")
        return

    # Dictionary to track users in each channel
    channel_users = defaultdict(list)
    user_channels = {}

    # Regular expressions to parse log lines
    move_pattern = re.compile(r"<\d+:([^>]+)\(-1\)>.*Moved .* to (\S+)")
    disconnect_pattern = re.compile(r"<\d+:([^>]+)\(-1\)>.*Connection closed:")

    # Process the log file line by line
    with open(logfile, "r") as f:
        for line in f:
            # Check if the line represents a "Moved" action
            move_match = move_pattern.search(line)
            if move_match:
                user_id = move_match.group(1)
                if user_id in {"Mic1", "Mic2", "Mic3", "Mic4", "Mic5", "Mic6"}:
                    continue
                channel = move_match.group(2)

                # Remove the user from their current channel, if any
                if user_id in user_channels:
                    current_channel = user_channels[user_id]
                    if user_id in channel_users[current_channel]:
                        channel_users[current_channel].remove(user_id)

                if channel == "Root[0:-1]":
                    continue
                # Add the user to the new channel
                user_channels[user_id] = channel
                channel_users[channel].append(user_id)
                continue

            # Check if the line represents a "Connection closed" event
            disconnect_match = disconnect_pattern.search(line)
            if disconnect_match:
                user_id = disconnect_match.group(1)
                if user_id in user_channels:
                    current_channel = user_channels[user_id]
                    if user_id in channel_users[current_channel]:
                        channel_users[current_channel].remove(user_id)
                    del user_channels[user_id]
                continue

    # Find the last non-empty channel
    non_empty_channels = [channel for channel, users in sorted(channel_users.items()) if users]
    if not non_empty_channels:
        print("Mic1: None")
        return
    last_non_empty_channel = non_empty_channels[-1]
    
    cnt = 0
    # Print the final state of channels and their users up to the last non-empty channel
    for channel, users in sorted(channel_users.items()):
        channel_name = channel.split('[')[0]
        if len(users) > 1:
            user_names = " & ".join(users)
        elif len(users) == 0:
            user_names = "None"
        else:
            user_names = users[0]
        print(f"{channel_name}: {user_names}")
        cnt += 1
        if channel == last_non_empty_channel:
            if cnt == 5:
                print(f"Mic6: None")
            break


if __name__ == "__main__":
    # Define the log file path
    logfile = os.path.expanduser("/var/log/mumble-server/mumble-server.log")
    parse_log(logfile)
