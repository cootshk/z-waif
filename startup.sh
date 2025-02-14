#!/usr/bin/env bash
if [[ "$1" == "--help" ]]; then
    echo "Usage: ./startup.sh [--help] [--reinstall] [--update] [--keep-logs] [--log-file FILE] [--python-binary BIN] [main_file]"
    echo "Options:"
    echo "  --help          Show this help message and exit"
    echo "  --reinstall     Reinstall dependencies"
    echo "  --update        Update pip packages"
    echo "  --keep-logs     Appends logs to an old log file instead of overwriting it"
    echo "  --log-file      Specify the log file to use (default: log.txt)"
    echo "  --python-binary Specify the python binary to use (default: python3.11)"
    echo "  main_file       Specify the main file to run (default: main.py)"
    exit 0
fi

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --reinstall)
            export REINSTALL=1
            shift
            ;;
        --update)
            export UPDATE_PIP=1
            shift
            ;;
        --keep-logs)
            export KEEP_LOGS=1
            shift
            ;;
        --log-file)
            export LOG_FILE="$2"
            shift 2
            ;;
        --python-binary)
            export PY="$2"
            shift 2
            ;;
        *)
            if [[ -z "$MAIN_FILE" ]]; then
                export MAIN_FILE="$1"
            else 
                echo "Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check for macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Check for root user
    if [[ "$EUID" != "0" && -z "$ALLOW_NONROOT" ]]; then
        echo "Please run this script as root on mac."
        exit 2
    fi
fi
# TODO: does linux need sudo?

# If no python binary is specified, use python3.11
if [[ -z "$PY" ]]; then
    export PY="python3.11"
fi
# Python version
export PYTHON_VERSION=$($PY --version)
if [[ -z "$PYTHON_VERSION" ]]; then
    echo "Python is not installed or not found in PATH."
    exit 1
fi
# Parse "Python x.y.z", get y
export PYTHON_VERSION=$(echo "$PYTHON_VERSION" | grep "\\..*\\." | cut -d "." -f 2)

# Check python version
if [[ "$PYTHON_VERSION" != "11" ]]; then    
    echo "Please use Python 3.11."
    exit 1
fi

# Set script dir to this file's dir
export SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Set the log file path
if [[ -z "$LOG_FILE" ]]; then
    export LOG_FILE="$SCRIPT_DIR/log.txt"
fi
# Move into the script dir
cd "$SCRIPT_DIR"
# Regenerate the log file if it doesn't exist
if [[ "$KEEP_LOGS" != "1" ]]; then
    # Remove the log file if it exists
    if [ -f "$LOG_FILE" ]; then
        echo "" > "$LOG_FILE" # Clear the log file
        # Don't rm -rf because then it is owned by root (Mac)
    fi
fi
if [[ ! -f "$LOG_FILE" ]]; then
    # Create the log file if it doesn't exist
    touch "$LOG_FILE"
    if [[ "$KEEP_LOGS" != "1" ]]; then
        echo "Regenerating log file..."
    else 
        echo "Log file not found, creating one at $LOG_FILE!"
    fi
fi
# Put the python version into the log file
echo "Python Version: $($PY --version)" | tee -a "$LOG_FILE"
# Check if the venv should be reinstalled
if [[ "$REINSTALL" == "1" ]]; then
    echo "Reinstalling dependencies..."
    rm -rf venv
fi
# Python venv
if [[ ! -d "venv" ]]; then
    # First install
    echo "Creating venv..."
    $PY -m venv venv
    export REINSTALL=1
fi
# Load the venv
source ./venv/bin/activate

# Run the script with ./startup.sh --update to update pip
if [[ "$UPDATE" == "1" || "$REINSTALL" == "1" ]]; then
    echo "Updating..."
    $PY -m pip install --upgrade pip | tee -a "$LOG_FILE"
    # Install PyTorch, torchvision, and torchaudio from a specific index URL
    $PY -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 | tee -a "$LOG_FILE"
    # Install openai-whisper from the GitHub repository
    $PY -m pip install git+https://github.com/openai/whisper.git | tee -a "$LOG_FILE"
    # Other deps
    # $PY -m pip install -U pywin32 | tee -a "$LOG_FILE"
    $PY -m pip install -r requirements.txt | tee -a "$LOG_FILE"
fi


# if main file somehow still isn't set
if [[ -z "$MAIN_FILE" ]]; then
    export MAIN_FILE="main.py"
fi
# Run the main file
if [[ "$OSTYPE" == "darwin"* ]]; then
    open http://localhost:7864 &
fi
$PY "$MAIN_FILE" | tee -a "$LOG_FILE"
STATUS=$?
# Deactivate venv
deactivate
# Error handling
if [[ $STATUS -ne 0 && $STATUS -ne 130 ]]; then # 0: exit success, 130: Ctrl+C
    echo "Error: $MAIN_FILE exited with status $STATUS"
    echo "See the log file for more info."
    exit $STATUS
    # Pause the script
    read -p "Press enter to continue..."
fi
# End of script
