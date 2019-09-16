# Common functions used by make-* scripts

function encode() {
    cat ${1} | base64 | tr -d '\r' | tr -d '\n'
}
