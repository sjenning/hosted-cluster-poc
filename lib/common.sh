function encode() {
  cat ${1} | base64 | tr -d '\n' | tr -d '\r'
}