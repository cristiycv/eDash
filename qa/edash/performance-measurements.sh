#!/bin/bash
set -u


DATADIR=./benchmark-datadir
SHA256CMD="$(command -v sha256sum || echo shasum)"
SHA256ARGS="$(command -v sha256sum >/dev/null || echo '-a 256')"

function edash_rpc {
    ./src/edash-cli -datadir="$DATADIR" -rpcuser=user -rpcpassword=password -rpcport=5983 "$@"
}

function edash_rpc_slow {
    # Timeout of 1 hour
    edash_rpc -rpcclienttimeout=3600 "$@"
}

function edash_rpc_veryslow {
    # Timeout of 2.5 hours
    edash_rpc -rpcclienttimeout=9000 "$@"
}

function edash_rpc_wait_for_start {
    edash_rpc -rpcwait getinfo > /dev/null
}

function edashd_generate {
    edash_rpc generate 101 > /dev/null
}

function extract_benchmark_datadir {
    if [ -f "$1.tar.xz" ]; then
        # Check the hash of the archive:
        "$SHA256CMD" $SHA256ARGS -c <<EOF
$2  $1.tar.xz
EOF
        ARCHIVE_RESULT=$?
    else
        echo "$1.tar.xz not found."
        ARCHIVE_RESULT=1
    fi
    if [ $ARCHIVE_RESULT -ne 0 ]; then
        edashd_stop
        echo
        echo "Please download it and place it in the base directory of the repository."
        exit 1
    fi
    xzcat "$1.tar.xz" | tar x
}

function use_200k_benchmark {
    rm -rf benchmark-200k-UTXOs
    extract_benchmark_datadir benchmark-200k-UTXOs dc8ab89eaa13730da57d9ac373c1f4e818a37181c1443f61fd11327e49fbcc5e
    DATADIR="./benchmark-200k-UTXOs/node$1"
}

function edashd_start {
    case "$1" in
        sendtoaddress|loadwallet|listunspent)
            case "$2" in
                200k-recv)
                    use_200k_benchmark 0
                    ;;
                200k-send)
                    use_200k_benchmark 1
                    ;;
                *)
                    echo "Bad arguments to edashd_start."
                    exit 1
            esac
            ;;
        *)
            rm -rf "$DATADIR"
            mkdir -p "$DATADIR/regtest"
            touch "$DATADIR/edash.conf"
    esac
    ./src/edashd -regtest -datadir="$DATADIR" -rpcuser=user -rpcpassword=password -rpcport=5983 -showmetrics=0 &
    edashD_PID=$!
    edash_rpc_wait_for_start
}

function edashd_stop {
    edash_rpc stop > /dev/null
    wait $edashD_PID
}

function edashd_massif_start {
    case "$1" in
        sendtoaddress|loadwallet|listunspent)
            case "$2" in
                200k-recv)
                    use_200k_benchmark 0
                    ;;
                200k-send)
                    use_200k_benchmark 1
                    ;;
                *)
                    echo "Bad arguments to edashd_massif_start."
                    exit 1
            esac
            ;;
        *)
            rm -rf "$DATADIR"
            mkdir -p "$DATADIR/regtest"
            touch "$DATADIR/edash.conf"
    esac
    rm -f massif.out
    valgrind --tool=massif --time-unit=ms --massif-out-file=massif.out ./src/edashd -regtest -datadir="$DATADIR" -rpcuser=user -rpcpassword=password -rpcport=5983 -showmetrics=0 &
    edashD_PID=$!
    edash_rpc_wait_for_start
}

function edashd_massif_stop {
    edash_rpc stop > /dev/null
    wait $edashD_PID
    ms_print massif.out
}

function edashd_valgrind_start {
    rm -rf "$DATADIR"
    mkdir -p "$DATADIR/regtest"
    touch "$DATADIR/edash.conf"
    rm -f valgrind.out
    valgrind --leak-check=yes -v --error-limit=no --log-file="valgrind.out" ./src/edashd -regtest -datadir="$DATADIR" -rpcuser=user -rpcpassword=password -rpcport=5983 -showmetrics=0 &
    edashD_PID=$!
    edash_rpc_wait_for_start
}

function edashd_valgrind_stop {
    edash_rpc stop > /dev/null
    wait $edashD_PID
    cat valgrind.out
}

function extract_benchmark_data {
    if [ -f "block-107134.tar.xz" ]; then
        # Check the hash of the archive:
        "$SHA256CMD" $SHA256ARGS -c <<EOF
4bd5ad1149714394e8895fa536725ed5d6c32c99812b962bfa73f03b5ffad4bb  block-107134.tar.xz
EOF
        ARCHIVE_RESULT=$?
    else
        echo "block-107134.tar.xz not found."
        ARCHIVE_RESULT=1
    fi
    if [ $ARCHIVE_RESULT -ne 0 ]; then
        edashd_stop
        echo
        echo "Please generate it using qa/edash/create_benchmark_archive.py"
        echo "and place it in the base directory of the repository."
        echo "Usage details are inside the Python script."
        exit 1
    fi
    xzcat block-107134.tar.xz | tar x -C "$DATADIR/regtest"
}


if [ $# -lt 2 ]
then
    echo "$0 : At least two arguments are required!"
    exit 1
fi

# Precomputation
case "$1" in
    *)
        case "$2" in
            verifyjoinsplit)
                edashd_start "${@:2}"
                RAWJOINSPLIT=$(edash_rpc zcsamplejoinsplit)
                edashd_stop
        esac
esac

case "$1" in
    time)
        edashd_start "${@:2}"
        case "$2" in
            sleep)
                edash_rpc zcbenchmark sleep 10
                ;;
            parameterloading)
                edash_rpc zcbenchmark parameterloading 10
                ;;
            createjoinsplit)
                edash_rpc zcbenchmark createjoinsplit 10 "${@:3}"
                ;;
            verifyjoinsplit)
                edash_rpc zcbenchmark verifyjoinsplit 1000 "\"$RAWJOINSPLIT\""
                ;;
            solveequihash)
                edash_rpc_slow zcbenchmark solveequihash 50 "${@:3}"
                ;;
            verifyequihash)
                edash_rpc zcbenchmark verifyequihash 1000
                ;;
            validatelargetx)
                edash_rpc zcbenchmark validatelargetx 10 "${@:3}"
                ;;
            trydecryptnotes)
                edash_rpc zcbenchmark trydecryptnotes 1000 "${@:3}"
                ;;
            incnotewitnesses)
                edash_rpc zcbenchmark incnotewitnesses 100 "${@:3}"
                ;;
            connectblockslow)
                extract_benchmark_data
                edash_rpc zcbenchmark connectblockslow 10
                ;;
            sendtoaddress)
                edash_rpc zcbenchmark sendtoaddress 10 "${@:4}"
                ;;
            loadwallet)
                edash_rpc zcbenchmark loadwallet 10 
                ;;
            listunspent)
                edash_rpc zcbenchmark listunspent 10
                ;;
            *)
                edashd_stop
                echo "Bad arguments to time."
                exit 1
        esac
        edashd_stop
        ;;
    memory)
        edashd_massif_start "${@:2}"
        case "$2" in
            sleep)
                edash_rpc zcbenchmark sleep 1
                ;;
            parameterloading)
                edash_rpc zcbenchmark parameterloading 1
                ;;
            createjoinsplit)
                edash_rpc_slow zcbenchmark createjoinsplit 1 "${@:3}"
                ;;
            verifyjoinsplit)
                edash_rpc zcbenchmark verifyjoinsplit 1 "\"$RAWJOINSPLIT\""
                ;;
            solveequihash)
                edash_rpc_slow zcbenchmark solveequihash 1 "${@:3}"
                ;;
            verifyequihash)
                edash_rpc zcbenchmark verifyequihash 1
                ;;
            validatelargetx)
                edash_rpc zcbenchmark validatelargetx 1
                ;;
            trydecryptnotes)
                edash_rpc zcbenchmark trydecryptnotes 1 "${@:3}"
                ;;
            incnotewitnesses)
                edash_rpc zcbenchmark incnotewitnesses 1 "${@:3}"
                ;;
            connectblockslow)
                extract_benchmark_data
                edash_rpc zcbenchmark connectblockslow 1
                ;;
            sendtoaddress)
                edash_rpc zcbenchmark sendtoaddress 1 "${@:4}"
                ;;
            loadwallet)
                # The initial load is sufficient for measurement
                ;;
            listunspent)
                edash_rpc zcbenchmark listunspent 1
                ;;
            *)
                edashd_massif_stop
                echo "Bad arguments to memory."
                exit 1
        esac
        edashd_massif_stop
        rm -f massif.out
        ;;
    valgrind)
        edashd_valgrind_start
        case "$2" in
            sleep)
                edash_rpc zcbenchmark sleep 1
                ;;
            parameterloading)
                edash_rpc zcbenchmark parameterloading 1
                ;;
            createjoinsplit)
                edash_rpc_veryslow zcbenchmark createjoinsplit 1 "${@:3}"
                ;;
            verifyjoinsplit)
                edash_rpc zcbenchmark verifyjoinsplit 1 "\"$RAWJOINSPLIT\""
                ;;
            solveequihash)
                edash_rpc_veryslow zcbenchmark solveequihash 1 "${@:3}"
                ;;
            verifyequihash)
                edash_rpc zcbenchmark verifyequihash 1
                ;;
            trydecryptnotes)
                edash_rpc zcbenchmark trydecryptnotes 1 "${@:3}"
                ;;
            incnotewitnesses)
                edash_rpc zcbenchmark incnotewitnesses 1 "${@:3}"
                ;;
            connectblockslow)
                extract_benchmark_data
                edash_rpc zcbenchmark connectblockslow 1
                ;;
            *)
                edashd_valgrind_stop
                echo "Bad arguments to valgrind."
                exit 1
        esac
        edashd_valgrind_stop
        rm -f valgrind.out
        ;;
    valgrind-tests)
        case "$2" in
            gtest)
                rm -f valgrind.out
                valgrind --leak-check=yes -v --error-limit=no --log-file="valgrind.out" ./src/edash-gtest
                cat valgrind.out
                rm -f valgrind.out
                ;;
            test_bitcoin)
                rm -f valgrind.out
                valgrind --leak-check=yes -v --error-limit=no --log-file="valgrind.out" ./src/test/test_bitcoin
                cat valgrind.out
                rm -f valgrind.out
                ;;
            *)
                echo "Bad arguments to valgrind-tests."
                exit 1
        esac
        ;;
    *)
        echo "Invalid benchmark type."
        exit 1
esac

# Cleanup
rm -rf "$DATADIR"
