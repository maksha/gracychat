#!/bin/bash

SCRIPT_NAME=$(basename $0)
LAMBDA_FUNCTION_S3KEY="lambda_package"
LAMBDA_LAYER_S3KEY="python_layer"

usage() {
    echo -e "$SCRIPT_NAME: Package Lambda function and dependencies into ZIP archives.\n"
    echo -e "  Run this script from the project root directory.\n"
    echo -e "  Usage: \n    $SCRIPT_NAME <lambda_function_filename> <layer_requirements_filename>"
    echo -e "  Example: \n    $SCRIPT_NAME lambda/lambda_function.py lambda/requirements.txt\n"
    exit 1
}

get_zip_info() {
    local zip_file=$1
    local info=$(unzip -l "$zip_file" | tail -n 1)
    local num_files=$(echo "$info" | awk '{print $2}')
    local total_size=$(echo "$info" | awk '{print $1}')
    echo "$num_files file(s), $total_size byte(s)"
}

if [ "$#" -ne 2 ]; then
    usage
fi

LAMBDA_FUNCTION_FILENAME=$1
LAYER_REQUIREMENTS_FILENAME=$2

if [ ! -f "$LAMBDA_FUNCTION_FILENAME" ]; then
    echo "Error: Lambda function file '$LAMBDA_FUNCTION_FILENAME' not found!"
    exit 1
fi

if [ ! -f "$LAYER_REQUIREMENTS_FILENAME" ]; then
    echo "Error: Requirements file '$LAYER_REQUIREMENTS_FILENAME' not found!"
    exit 1
fi

# Create a temporary directory in the current directory
TEMP_DIR="TEMP_DIR"
mkdir -p "$TEMP_DIR/python"

# Copy the lambda function file to the temporary directory 
# and get the Python dependencies ready for packaging
cp "$LAMBDA_FUNCTION_FILENAME" "$TEMP_DIR/"
pip install -r "$LAYER_REQUIREMENTS_FILENAME" -t "$TEMP_DIR/python"

# ZIP archives for the lambda layer and lambda function
cd "$TEMP_DIR" || exit
zip -r9 ../"$LAMBDA_FUNCTION_S3KEY".zip "$(basename "$LAMBDA_FUNCTION_FILENAME")"
echo "----"
zip -r9 ../"$LAMBDA_LAYER_S3KEY".zip python/
echo "----"

# Clean up the temporary directory
cd ..
rm -rf "$TEMP_DIR"

# Display the location of the ZIP files
echo -e "Packaging complete. Packages are ready for upload:"
echo -e " \e[32m\u2714\e[0m - $(pwd)/"$LAMBDA_FUNCTION_S3KEY".zip ($(get_zip_info $(pwd)/"$LAMBDA_FUNCTION_S3KEY".zip))"
echo -e " \e[32m\u2714\e[0m - $(pwd)/"$LAMBDA_LAYER_S3KEY".zip ($(get_zip_info $(pwd)/"$LAMBDA_LAYER_S3KEY".zip))\n"