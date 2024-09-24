#!/bin/bash

# Function to load .env file
load_env() {
    if [ -f .env ]; then
        set -o allexport
        source <(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' .env)
        set +o allexport
        if [ ! -z "$ENV" ]; then
          echo "ENV=$ENV"
        fi
        if [ ! -z "$FORCE_ENV" ]; then
          echo "NODE_ENV=$NODE_ENV"
        fi
        if [ ! -z "$FORCE_ENV" ]; then
          echo "FORCE_ENV=$FORCE_ENV"
        fi
    else
        echo "ERROR: .env file is not valid!"
        exit 1
    fi
}

# A function to display a usage message:
usage() {
    echo "Usage: $0 [-w|--workspace <workspace>] [-b|--bin <bin>] [-k|--skip-check] [-n|--skip-clean] [-r|--root] [-e|--export-only] [-u|--build-only] [--release-fast]"
}

# Main execution starts here
load_env

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
RELEASE_FLAG="release"
RUST_HOST=$(rustc -vV | sed -n 's/host: //p')
TARGET="${BUILD_TARGET:-"${RUST_HOST}"}"
echo "BUILDER_BIN=$BUILDER_BIN"
BUILDER_BIN="${BUILDER_BIN:-"cargo build"}"
# TARGET="wasm32-wasi"

# Check if no arguments were passed
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

# Parse the command-line arguments:
OPTIONS=$(getopt -o w:b:knreu --long workspace:,bin:,skip-check,skip-clean,root,export-only,build-only,release-fast -- "$@")

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
        --release-fast)
            RELEASE_FLAG="release-fast"
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

copying_files() {
  local targets=$1
  local destination=$2

  for target in $targets; do
    target_base=$(basename "$target")
    # Construct the copy command
    COPY_COMMAND="cp '${target}' '${destination}/${target_base}'"

    # Execute the copy command
    eval $COPY_COMMAND

    # Verify the copy
    if [ -f "${destination}/${target_base}" ]; then
        echo "✅ ${target_base} ==> ${destination}/${target_base}! Copied successfully!"
    else
        echo "Failed to copy ${target_base}"
        exit 1
    fi
  done
}

{
  if ! $EXPORT_ONLY_FLAG; then
    echo "Releasing to $TARGET with options:
    workspace: $WORKSPACE, bin: $BIN, skip_check: $SKIP_CHECK_FLAG, skip_clean: $SKIP_CLEAN_FLAG,
    selective_build: $SELECTIVE_BUILD_FLAG, root_build: $ROOT_BUILD_FLAG,
    build_only: $BUILD_ONLY_FLAG, export_only: $EXPORT_ONLY_FLAG,
    release_flag: $RELEASE_FLAG"

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
      $BUILDER_BIN --profile $RELEASE_FLAG --target $TARGET || {
        echo -e "\033[31mCargo build failed for root! ❌\033[0m"
        exit 1
      }
    elif $SELECTIVE_BUILD_FLAG ; then
      if $BIN_BUILD_FLAG ; then
        cd $WORKSPACE
        $BUILDER_BIN --bin $BIN --profile $RELEASE_FLAG --target $TARGET || {
          echo -e "\033[31mCargo build failed for binary $BIN! ❌\033[0m"
          exit 1
        }
      else
        $BUILDER_BIN -p $WORKSPACE --profile $RELEASE_FLAG --target $TARGET || {
          echo -e "\033[31mCargo build failed for package $WORKSPACE! ❌\033[0m"
          exit 1
        }
      fi
    else
      $BUILDER_BIN --workspace --profile $RELEASE_FLAG --target $TARGET || {
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
    RELEASE_DIR="./target/${TARGET}/${RELEASE_FLAG}"

    # Define the destination directory for the binaries
    DESTINATION_DIR="./bin"

    # Remove the destination directory if it exists
    echo "Removing ${DESTINATION_DIR}..."
    rm -rf ${DESTINATION_DIR}

    # Create the destination directory
    echo "Creating ${DESTINATION_DIR}..."
    mkdir -p $DESTINATION_DIR

    # Extract the binary names from Cargo.toml
    # Assume [[bin]] sections contain a 'name = "binary_name"' line
    # BIN_NAMES=$(grep -A 1 "\[\[bin\]\]" $CARGO_TOML_PATH | grep "name =" | cut -d '"' -f2)
    # fetch all .exe(s) inside target/release/* only, don't recursively
    # BIN_NAMES=$(find "$RELEASE_DIR" -maxdepth 1 -type f \( -name '*.exe' -o -perm -111 \) -printf '%f\n')

    echo "Searching for binaries in ${RELEASE_DIR}..."
    BIN_NAMES=$(find "$RELEASE_DIR" -maxdepth 1 -type f \( -name '*.exe' -o -executable \) ! -name '*.d' -print)
    ENV_NAMES=$(find "." -maxdepth 1 -type f \( -name '*.env*' \) ! -print)

    if [ -z "$BIN_NAMES" ]; then
        echo "No binaries found in ${RELEASE_DIR}"
        exit 1
    fi

    # Iterate over the binary names and copy them to the destination directory
    echo ""
    echo "Copying ${BIN_NAMES}..."
    echo ""
    copying_files "$BIN_NAMES" "$DESTINATION_DIR"
    echo "✅ All binaries have been copied!"

    cp ${CARGO_TOML_PATH} ${DESTINATION_DIR}/
    echo "✅ ${CARGO_TOML_PATH} ==> ${DESTINATION_DIR}/${CARGO_TOML_PATH} copied!"

    echo ""
    copying_files "$ENV_NAMES" "$DESTINATION_DIR"
    echo "✅ All env(s) have been copied!"

    echo ""
    cp -rv ./storage ${DESTINATION_DIR}/ || {
      echo -e "\033[31mStorage copy failed! ❌\033[0m"
    }
    echo "STORAGE copy done."

    cp -rv ./config ${DESTINATION_DIR}/ || {
      echo -e "\033[31mConfig copy failed! ❌\033[0m"
    }
    echo "CONFIG copy done."
  else
    echo "Build only option enabled, skipping export step... 🛠️"
  fi
}
