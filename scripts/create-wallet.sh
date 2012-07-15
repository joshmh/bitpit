TMP=scratch
OUT=out
PASS="the secret pass phrase"

rm -rf $TMP
rm -rf $OUT

mkdir $TMP
mkdir $OUT

read -s -p "Enter Your Password: " pass
export GPG_PASS=$pass

./expect.sh

echo
echo "Creating split keys for seed..."
./s-expect.sh
sed -n -e 2p $TMP/splitted.dat > $OUT/split-key1.dat
sed -n -e 3p $TMP/splitted.dat > $OUT/split-key2.dat
sed -n -e 4p $TMP/splitted.dat > $OUT/split-key3.dat
echo "Done."

export GPG_PASS=

mv $TMP/vault.dat $OUT
mv $TMP/vault.dat.seed.asc $OUT

#rm -rf $TMP
