# Assume two keys (key1.dat, key2.dat), or ask for password

scripts_dir=/usr/local/bin

keys_dir=$HOME/split-keys
vault_dir=$HOME/vault

key1=$keys_dir/key1.dat
key2=$keys_dir/key2.dat
encrypted_seed=$vault_dir/vault.dat.seed.asc
decrypted_seed=$vault_dir/vault.dat.seed
wallet=$vault_dir/vault.dat
tx_file=$HOME/tx.dat

echo
echo "*** bitpit version 0.1 ***"
echo
echo "This program will create an offline Bitcoin transaction for transferring Bitcoins from your cold storage."
echo "The program expects the following files in the \"vault\" directory:"
echo
echo "vault.dat (The wallet file that was created on this computer)"
echo "vault.dat.seed.asc (The encrypted seed file that was created on this computer)"
echo
echo "...and, optionally, two of the three key files, named key1.dat and key2.dat. These should be in the \"split-keys\" directory, "
echo "not in the \"vault\" directory. You only need these if you've forgotten your pass phrase."
echo

if [ ! -f $wallet ]; then
	echo "----------------------------------------------------------------"
	echo
	echo "vault.dat wallet file is missing. Please copy that file and try again."
	echo
	exit
fi

if [ ! -f $encrypted_seed ]; then
	echo "----------------------------------------------------------------"
	echo
	echo "$encrypted_seed encrypted seed file is missing. Please copy that file and try again."
	echo
	exit
fi

read -p "What bitcoin address would you like to send to? " btc_address
read -p "How many bitcoins would you like to send? " amount

echo

if [ -f $key1 -a -f $key2 ]; then
	echo "Using split keys method."
	pass=`$scripts_dir/combine-expect.sh`
	export GPG_PASS=$pass
elif [ -f $key1 -o -f $key2 ]; then
	echo "You need at least two key files, called key1.dat and key2.dat"
	echo
	exit
else
	echo "Using pass phrase method."
	read -s -p "Please enter your pass phrase: " pass
	export GPG_PASS=$pass
fi

echo
echo "Decrypting wallet..."
$scripts_dir/gpg-expect.sh	
export GPG_PASS=
echo "Done."
echo

echo "Reseeding wallet..."
electrum -w $wallet reseed > /dev/null
echo "Done."
echo

echo "Creating transaction..."
electrum -w $wallet mktx $btc_address $amount > $tx_file
echo "Done."
echo

$scripts_dir/deseed-expect.sh
rm $decrypted_seed

echo "Your transaction is in the file tx.dat. Copy it to your online computer and run the command: "
echo "electrum sendtx `cat tx.dat`"
echo
echo "Alternatively, you can paste the contents of the file to a site such as bitsend.rowit.co.uk or brainwallet.org, and send it from there."
echo

rm -f $key1 $key2
