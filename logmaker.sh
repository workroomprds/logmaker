#!/bin/bash

# writes a busy log file for testing purposes
# 50 lines / second, 
# bins back to MAX_LINES every 10 mins (moving the file, and tail -F will object)
# picks from the systems, marks rare failures, has different info in messages

# Configuration parameters
LOG_FILE="/tmp/simulated_log.txt"
MAX_LINES=10000
SYSTEMS=("CORE" "NETWORK" "SERVICE-001" "HANDLERS")
WRITE_INTERVAL=0.02
TRIM_INTERVAL=60
FAILURE_PROBABILITY=5 #of 1000
WARNING_PROBABILITY=200 #of 1000
PID_FILE="/tmp/log_generator.pid"
CONTROL_FILE="/tmp/log_generator.control"

# Function to check if we can write to the log file
check_log_file() {
    if [ ! -e "$LOG_FILE" ]; then
        touch "$LOG_FILE" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Error: Cannot create log file $LOG_FILE. Check permissions or path."
            exit 1
        fi
    elif [ ! -w "$LOG_FILE" ]; then
        echo "Error: Cannot write to log file $LOG_FILE. Check permissions."
        exit 1
    fi
}

# Function to generate and append log entries
generate_logs() {
    while [ -f "$CONTROL_FILE" ]; do
        SYSTEM=${SYSTEMS[$RANDOM % ${#SYSTEMS[@]}]}
        
        LEVEL_RAND=$((RANDOM % 1000))
        if [ $LEVEL_RAND -lt $FAILURE_PROBABILITY ]; then
            LEVEL="failure"
        elif [ $LEVEL_RAND -lt $((FAILURE_PROBABILITY + WARNING_PROBABILITY)) ]; then
            LEVEL="warning"
        else
            LEVEL="info"
        fi

        LEVEL_RAND=$((RANDOM % 100))
        if [ $LEVEL_RAND -lt 5 ]; then
            LOG_MSG="found $((RANDOM % 100)) in $(tr -dc A-Za-z0-9 </dev/urandom | head -c 10)"
        elif [ $LEVEL_RAND -lt 20 ]; then
            LOG_MSG=$"$(tr -dc a-f0-9 </dev/urandom | head -c 8)"
        elif [ $LEVEL_RAND -lt 70 ]; then
            LOG_MSG=$((RANDOM % 10000))
        else
            LOG_MSG=" ... ... "
        fi
        
        log_entry="$(date '+%Y-%m-%d %H:%M:%S') - [$SYSTEM] [$LEVEL] Log entry: $LOG_MSG"
        
        if ! echo "$log_entry" >> "$LOG_FILE"; then
            echo "Error: Failed to write to log file. Stopping generator." >&2
            rm -f "$CONTROL_FILE"
            exit 1
        fi
        
        sleep $WRITE_INTERVAL
    done
}

# Function to trim the log file
trim_logs() {
    while [ -f "$CONTROL_FILE" ]; do
        if [ -f "$LOG_FILE" ]; then
            current_lines=$(wc -l < "$LOG_FILE")
            
            if [ "$current_lines" -gt "$MAX_LINES" ]; then
                # In-place truncation keeping last 1000 lines
                sed -i "1,$((current_lines - MAX_LINES))d" "$LOG_FILE"
            fi
        fi
        sleep $TRIM_INTERVAL
    done
}

# Function to start the log generator
start() {
    if [ -f "$PID_FILE" ]; then
        echo "Log generator is already running."
        exit 1
    fi
    
    check_log_file
    
    touch "$CONTROL_FILE"
    
    generate_logs &
    generate_pid=$!
    trim_logs &
    trim_pid=$!
    
    echo "$generate_pid $trim_pid" > "$PID_FILE"
    echo "Log generator started. PIDs: $generate_pid (generator), $trim_pid (trimmer)"
}

# Function to stop the log generator
stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo "Log generator is not running."
        exit 1
    fi
    
    read generate_pid trim_pid < "$PID_FILE"
    rm -f "$CONTROL_FILE"
    sleep 1
    kill $generate_pid $trim_pid 2>/dev/null
    rm -f "$PID_FILE"
    echo "Log generator stopped."
}

# Function to display status
status() {
    if [ -f "$PID_FILE" ]; then
        read generate_pid trim_pid < "$PID_FILE"
        echo "Log generator is running. PIDs: $generate_pid (generator), $trim_pid (trimmer)"
    else
        echo "Log generator is not running."
    fi
}

# Parse command line arguments
case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
