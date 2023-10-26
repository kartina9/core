# Read $CALLDATA from calldata.txt
CALLDATA=$(cat calldata.txt)

LENSHUB="0x7582177F9E536aB0b6c721e11f383C326F2Ad1D5"
GOVERNANCE="0x56ebd55b2DD089D91D14Ec131Ad41e8474684822"
GOVOWNER="0x532BbA5445e306cB83cF26Ef89842d4701330A45"

cast send --rpc-url mumbai --unlocked --from $GOVOWNER $GOVERNANCE "executeAsGovernance(address,bytes)" $LENSHUB $CALLDATA
