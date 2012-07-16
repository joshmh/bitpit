TMP=/tmp/scratch
OUT=$HOME/vault
SPLITS=$HOME/split-keys
SCRIPTS_DIR=/usr/local/bin

echo
echo "*** bitpit 0.1 ***"
echo
echo "This program creates a new Electrum wallet and encrypts the seed with your pass phrase."
echo "Additionally, the pass phrase is split into three files: key1.dat, key2.dat, and key2.dat."
echo "You should copy each of these files onto a different USB drive, and hide them in different locations."
echo
echo "If you ever forget your pass phrase, you will be able to reconstruct it with any two out of the three keys."
echo
echo "Resulting wallet files are in the newly created \"vault\" directory, and split keys are in the $SPLITS directory."
echo

rm -rf $TMP
rm -rf $OUT
rm -rf $SPLITS

mkdir -p $TMP
mkdir -p $OUT
mkdir -p $SPLITS

read -s -p "Enter Your Password: " pass
export GPG_PASS=$pass

echo
echo

$SCRIPTS_DIR/expect.sh

echo
echo "Creating split keys for seed..."
$SCRIPTS_DIR/s-expect.sh
sed -n -e 2p $TMP/splitted.dat > $SPLITS/key1.dat
sed -n -e 3p $TMP/splitted.dat > $SPLITS/key2.dat
sed -n -e 4p $TMP/splitted.dat > $SPLITS/key3.dat
echo "Done."

export GPG_PASS=

mv $TMP/vault.dat $OUT
mv $TMP/vault.dat.seed.asc $OUT

rm -rf $TMP
