#!/usr/bin/zsh
echo "adapt user, password, host, path to usdx before using this script"
exit 1
# This script configures Mumble clients with null sinks for audio routing.
# It starts multiple Mumble clients, each with its own null sink, and links them to the appropriate audio inputs.
killall mumble
pactl list modules | grep module-null-sink -B1 | grep -oE "#.*" | grep -oE "[0-9]+" | xargs -L1 pactl unload-module

# Function to start Mumble clients and configure sinks
start_mumble_client() {
  client_name=$1

  # Capture the current list of IDs from pw-link
  existing_ids_fl=$(pw-link -o -I | grep "Mumble:output_FL" | awk '{print $1}')
  existing_ids_fr=$(pw-link -o -I | grep "Mumble:output_FR" | awk '{print $1}')

  # Start Mumble with unique client name
  mumble -m -n mumble://$client_name@127.0.0.1/$client_name 1>/dev/null 2>/dev/null &

  # Create a null sink with a unique name
  pactl load-module module-null-sink media.class=Audio/Source/Virtual sink_name=$client_name channel_map=front-left,front-right 1>/dev/null 2>/dev/null
  while true; do
    wactive=$(xdotool getactivewindow)
    wname=$(xdotool getwindowname $wactive)
    if [[ $wname == Mumble* ]]; then
      sleep 0.5
      xdotool windowminimize $(xdotool getactivewindow)
      break
    fi
    sleep 0.5
  done
  pw-link -l -I | grep alsa | grep "|" | awk '{print $1}' | xargs -I{} pw-link -d {}

  # Wait for new unique IDs to appear
  while true; do
    current_ids_fl=$(pw-link -o -I | grep "Mumble:output_FL" | awk '{print $1}')
    current_ids_fr=$(pw-link -o -I | grep "Mumble:output_FR" | awk '{print $1}')
    new_ids_fl=$(echo "${current_ids_fl[@]}" "${existing_ids_fl[@]}" | tr ' ' '\n' | sort | uniq -u)
    new_ids_fr=$(echo "${current_ids_fr[@]}" "${existing_ids_fr[@]}" | tr ' ' '\n' | sort | uniq -u)
    new_ids_fl=${new_ids_fl//$'\n'/}
    new_ids_fr=${new_ids_fr//$'\n'/}
    if [[ "$new_ids_fl" != "" && "$new_ids_fr" != "" ]]; then
      # Update the IDs for outputs and inputs
      echo "connecting L: $new_ids_fl"
      pw-link "$new_ids_fl" ${1}:input_FL
      #pw-link "$new_ids_fr" ${1}:input_FR
      break
    fi
    sleep 0.1
  done
}

# Start Mumble clients for each mic
for i in `seq 1 6`; do
  start_mumble_client "Mic$i"
done


echo "Configuration completed."

while [[ $(iwconfig 2>/dev/null | grep -o "ESSID\:off" | wc -l) -gt 0 ]]; do; sleep 1; done

ip=`ip addr show OBwlan0 | grep "inet " | grep "dynamic" | grep -oE "[0-9]+(\.[0-9]+)*\/" | grep -oE "[0-9]+(\.[0-9]+)*"`

while [[ "$ip" = "" ]]; do; sleep 1; ip=`ip addr show OBwlan0 | grep "inet " | grep "dynamic" | grep -oE "[0-9]+(\.[0-9]+)*\/" | grep -oE "[0-9]+(\.[0-9]+)*"`; done

wget -q -O /dev/null -o /dev/null "http://user:password@freedns.afraid.org/nic/update?hostname=domain&address=$ip"

/path/to/usdx/ultrastardx &
