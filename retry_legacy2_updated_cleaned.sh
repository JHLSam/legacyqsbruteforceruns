#!/usr/bin/env bash

export POETRY_HOME="$HOME/.local"
export PATH="$POETRY_HOME/bin:$PATH"
#===============================INPUTS===============================
RPC_URL=""
export USERNAME="bob" #for testing
export PKEY=""
export API_TOKEN=""
export CHAT_ID=""
user=$(whoami)
desktop_path="$HOME/Desktop"
trader_path="trader-quickstart/trader"
service_num=$(whoami | grep -o '[0-9]\+')
#set threshold, 0.5 for legacy, whatever it is for new qs, I think 5? you could adjust it yourself but 0.61 is optimal for full run
THRESHOLD_XDAI=0.62
THRESHOLD_ACTIVITY=61
delay=50 #seconds, adjustable whatever you see works in action
#====================================================================


generate_report() {
	(cd $desktop_path/trader-quickstart/trader && /home/$user/.local/bin/poetry run python ../report.py) > $desktop_path/report_output.txt 2>&1
}

refresh_state() {
  generate_report

  status=$(grep "Status (on this machine)" $desktop_path/report_output.txt \
    | sed -r 's/\x1B\[[0-9;]*[mK]//g')
  echo "Updated status: $status"
  
  num_mech_txs=$(grep -oP 'Num\. Mech txs current epoch\s+\K\d+' $desktop_path/report_output.txt)
  num_mech_txs=${num_mech_txs:-0}
  echo "Updated num_mech_txs this epoch: $num_mech_txs"
  
  SAFE_ADDRESS=$(
  awk '
    /^Safe/ {in_safe=1; next}
    /^Owner\/Operator/ {in_safe=0}
    in_safe && /Address/ {print $2}
  ' $desktop_path/report_output.txt
	)
	echo "safe address: $SAFE_ADDRESS"
	
	SAFE_XDAI_BALANCE=$(
  awk '
    /^Safe/ {in_safe=1; next}
    /^Owner\/Operator/ {in_safe=0}
    in_safe && /xDAI Balance/ {print $3}
  ' $desktop_path/report_output.txt
	)
	echo "safe xdai balance: $SAFE_XDAI_BALANCE"
	
	if awk -v s="$SAFE_XDAI_BALANCE" -v t="$THRESHOLD_XDAI" 'BEGIN { exit !(s < t) }'; then
    AMOUNT=$(LC_NUMERIC=C awk -v s="$SAFE_XDAI_BALANCE" -v t="$THRESHOLD_XDAI" \
        'BEGIN { printf "%.2f", (t - s) + 0.01 }')
    /usr/bin/python3 $desktop_path/trader-quickstart/pub.py "$AMOUNT" "$status" "$num_mech_txs" "$service_num"
	fi
	
	#initialise
	AMOUNT=${AMOUNT:-0}
	echo "TOP_UP_AMOUNT_NEEDED: $AMOUNT"
	
	NUM_MECH_TRANSACTIONS_NEEDED_FOR_KPI=$((THRESHOLD_ACTIVITY - $num_mech_txs))
  	echo "MECH_REQUESTS_LEFT_TO_KPI: $NUM_MECH_TRANSACTIONS_NEEDED_FOR_KPI"
  
  	TOP_UP_AMOUNT_NEEDED_FOR_BRUTE_FORCE_RUNS=$(awk "BEGIN {printf \"%.2f\", ($NUM_MECH_TRANSACTIONS_NEEDED_FOR_KPI / 100) + $AMOUNT - 0.01}")
	echo "TOP_UP_AMOUNT_NEEDED_FOR_BRUTE_FORCE_RUNS:$TOP_UP_AMOUNT_NEEDED_FOR_BRUTE_FORCE_RUNS"
	
}

<<'COMMENT'
#alternative, ignore agent & owner/operator sections complately and just grrep target
SAFE_XDAI_BALANCE=$(
  sed -n '/^Safe/,/^Owner\/Operator/p' report.txt |
  grep 'xDAI Balance' |
  awk '{print $3}'
)
COMMENT

topup_for_normal_run() {
    #:
    if [ "$AMOUNT" -gt 0 ]; then
    	/usr/bin/python3 $desktop_path/trader-quickstart/topup.py "$RPC_URL" "$SAFE_ADDRESS" "$AMOUNT"
	else
		echo "SAFE BALANCE: $SAFE_XDAI_BALANCE already exceeds needed threshold XDAI: $THRESHOLD_XDAI, skipping topup"
	fi
}

topup_for_brute_force_run() {
    /usr/bin/python3 $desktop_path/trader-quickstart/topup.py "$RPC_URL" "$SAFE_ADDRESS" "$TOP_UP_AMOUNT_NEEDED_FOR_BRUTE_FORCE_RUNS"
}

halt_runs() {
	cd $desktop_path/trader-quickstart && ./stop_service.sh
	docker container prune --force
	docker system prune --force
}

run_space() {
	cd $desktop_path/trader-quickstart && ./run_service.sh
}

TOTAL_BRUTE_FORCE_RUNS=0
MAX_BRUTE_FORCE_RUNS=78

brute_force_run_loop() {
	local_runs=${1:-61}
	local_delay=${2:-45}
	#topup_for_brute_force_run
	
	for((i=1; i<=local_runs; i++)); do
	
		if [ "$TOTAL_BRUTE_FORCE_RUNS" -ge "$MAX_BRUTE_FORCE_RUNS" ]; then
            echo "🚫 Reached max brute force runs ($MAX_BRUTE_FORCE_RUNS). Stopping."
            return 1
        fi
        
        TOTAL_BRUTE_FORCE_RUNS=$((TOTAL_BRUTE_FORCE_RUNS + 1))
        
		echo "running $i of $1 runs"
		echo "run_service brute force"
		run_space
		sleep "$local_delay"
		done
		halt_runs
}

normal_run() {
	topup_for_normal_run
	run_space
}

refresh_state

while [ "$num_mech_txs" -lt "$THRESHOLD_ACTIVITY" ]
do

  if [ "$TOTAL_BRUTE_FORCE_RUNS" -ge "$MAX_BRUTE_FORCE_RUNS" ]; then
    echo "🚫 Global brute force limit reached ($MAX_BRUTE_FORCE_RUNS). Exiting loop."
    break
  fi
  echo "Current status=$status"
  echo "Current num_mech_txs=$num_mech_txs"
  echo "Total brute force runs so far=$TOTAL_BRUTE_FORCE_RUNS"

  # If service is running, stop it first
  if echo "$status" | grep -qiE "Running"; then
    echo "Service is Running → stopping it"
    halt_runs
    refresh_state
  fi

  # If KPI still not met, run brute force
  if echo "$status" | grep -qiE "Evicted|Stopped" && [ "$num_mech_txs" -lt "$THRESHOLD_ACTIVITY" ]; then
    echo "❌ KPI not met → running brute force loop"
    brute_force_run_loop "$NUM_MECH_TRANSACTIONS_NEEDED_FOR_KPI" "$delay"
    refresh_state
  fi
done

echo "✅ KPI threshold fulfilled or exited due to max runs threshold fulfilled"
echo "Final status=$status"
echo "Final num_mech_txs=$num_mech_txs"

halt_runs
