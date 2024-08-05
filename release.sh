#!/bin/bash

# Initialize our own variables:
WORKSPACE=""
BIN=""
SKIP_CHECK_FLAG=false
SKIP_CLEAN_FLAG=false
SELECTIVE_BUILD_FLAG=false
BIN_BUILD_FLAG=false
ROOT_BUILD_FLAG=false
EXPORT_ONLY_FLAG=false
BUILD_ONLY_FLAG=false
TARGET="x86_64-pc-windows-msvc"
# TARGET="wasm32-wasi"

# A function to display a usage message:
usage() {
    echo "Usage: $0 [-w|--workspace <workspace>] [-b|--bin <bin>] [-k|--skip-check] [-n|--skip-clean] [-r|--root] [--export-only] [--build-only]"
}

# Check if no arguments were passed
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

# Parse the command-line arguments:
OPTIONS=$(getopt -o w:b:knreu --long workspace:,bin:,skip-check,skip-clean,root,export-only,build-only -- "$@")

if [ $? -ne 0 ]; then
    # getopt has complained about wrong arguments to stdout
    usage
    exit 1
fi

eval set -- "$OPTIONS"

while true; do
    case "$1" in
        -w|--workspace)
            SELECTIVE_BUILD_FLAG=true
            WORKSPACE="$2"
            shift 2
            ;;
        -b|--bin)
            BIN_BUILD_FLAG=true
            BIN="$2"
            shift 2
            ;;
        -k|--skip-check)
            SKIP_CHECK_FLAG=true
            shift
            ;;
        -n|--skip-clean)
            SKIP_CLEAN_FLAG=true
            shift
            ;;
        -r|--root)
            ROOT_BUILD_FLAG=true
            shift
            ;;
        -e|--export-only)
            EXPORT_ONLY_FLAG=true
            shift
            ;;
        -u|--build-only)
            BUILD_ONLY_FLAG=true
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Internal error!"
            exit 1
            ;;
    esac
done

{
  if ! $EXPORT_ONLY_FLAG; then
    echo "Releasing with options: workspace: $WORKSPACE, bin: $BIN, skip_check: $SKIP_CHECK_FLAG, skip_clean: $SKIP_CLEAN_FLAG, selective_build: $SELECTIVE_BUILD_FLAG, root_build: $ROOT_BUILD_FLAG, build_only: $BUILD_ONLY_FLAG, export_only: $EXPORT_ONLY_FLAG"

    # Cleaning previous builds
    if ! $SKIP_CLEAN_FLAG ; then
      cargo clean
    else
      echo "Skipping clean..."
    fi

    # Run cargo clippy and capture any errors
    if ! $SKIP_CHECK_FLAG ; then
      cargo clippy --color=always --workspace --fix --allow-dirty --allow-staged -- -D clippy::panic -W clippy::all || {
          echo -e "Clippy reported errors! ❌"
          exit 1
      }
      cargo fmt --all
    else
      echo "Skipping check..."
    fi

    WORKDIR=$(pwd)

    # Build based on flags and capture errors
    if $ROOT_BUILD_FLAG ; then
      cargo build -r --target $TARGET || {
        echo -e "\033[31mCargo build failed for root! ❌\033[0m"
        exit 1
      }
    elif $SELECTIVE_BUILD_FLAG ; then
      if $BIN_BUILD_FLAG ; then
        cd $WORKSPACE
        cargo build --bin $BIN -r --target $TARGET || {
          echo -e "\033[31mCargo build failed for binary $BIN! ❌\033[0m"
          exit 1
        }
      else
        cargo build -p $WORKSPACE -r --target $TARGET || {
          echo -e "\033[31mCargo build failed for package $WORKSPACE! ❌\033[0m"
          exit 1
        }
      fi
    else
      cargo build --workspace -r --target $TARGET || {
        echo -e "\033[31mCargo build failed for workspace! ❌\033[0m"
        exit 1
      }
    fi

    cd $WORKDIR

    # If we reached this point, it means build was successful
    echo "Release binaries success! ✅"
  else
    echo "Exporting previously built binaries... 🛠️"
  fi

  if ! $BUILD_ONLY_FLAG; then
    # Define the path to the Cargo.toml file
    CARGO_TOML_PATH="./Cargo.toml"

    # Define the release directory where binaries are located
    RELEASE_DIR="./target/$TARGET/release"

    # Define the destination directory for the binaries
    DESTINATION_DIR="./bin"

    # Remove the destination directory if it exists
    echo "Removing ${DESTINATION_DIR}..."
    rm -r ${DESTINATION_DIR}

    # Create the destination directory if it does not exist
    mkdir -p $DESTINATION_DIR

    # Extract the binary names from Cargo.toml
    # Assume [[bin]] sections contain a 'name = "binary_name"' line
    # BIN_NAMES=$(grep -A 1 "\[\[bin\]\]" $CARGO_TOML_PATH | grep "name =" | cut -d '"' -f2)
    # fetch all .exe(s) inside target/release/* only, don't recursively
    BIN_NAMES=$(find "$RELEASE_DIR" -maxdepth 1 -type f -name '*.exe' -printf '%f\n')

    # Iterate over the binary names and copy them to the destination directory
    for BIN_NAME in $BIN_NAMES; do
        # Construct the copy command
        COPY_COMMAND="cp ${RELEASE_DIR}/${BIN_NAME} ${DESTINATION_DIR}/${BIN_NAME}"

        # Execute the copy command
        echo "Copying ${BIN_NAME}..."
        $COPY_COMMAND
    done
    echo "All binaries have been copied."

    cp $CARGO_TOML_PATH ${DESTINATION_DIR}/
    echo "CARGO_TOML_PATH copied."

    cp .env ${DESTINATION_DIR}/ || {
      echo -e "\033[31m.env copy failed! ❌\033[0m"
    }
    echo "ENV copy done."

    cp -R ./storage ${DESTINATION_DIR}/ || {
      echo -e "\033[31mStorage copy failed! ❌\033[0m"
    }
    echo "STORAGE copy done."
  else
    echo "Build only option enabled, skipping export step... 🛠️"
  fi
}
