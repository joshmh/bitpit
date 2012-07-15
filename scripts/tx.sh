# Assume two keys (key1.dat, key2.dat), or ask for password

key1=key1.dat
key2=key2.dat
encrypted_seed=vault.dat.seed.asc

echo
echo "*** bitpit version 0.1 ***"
echo
echo "This program will create an offline Bitcoin transaction for transferring Bitcoins from your cold storage."
echo "The program expects the following files in your current directory:"
echo
echo "vault.dat (The wallet file that was created on this computer)"
echo "vault.dat.seed.asc (The encrypted seed file that was created on this computer)"
echo "key1.dat and key2.dat [optional] (If you have forgotten your password, you'll need 2 of the 3 original key files)"
echo

if [ ! -f vault.dat ]; then
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

if [ -f $key1 -a -f $key2 ]; then
	echo "files exist"
elif [ -f $key1 -o -f $key2 ]; then
	echo "You need at least two key files, called key1.dat and key2.dat"
else
	echo "Using pass phrase method."
	read -s -p "Please enter your pass phrase: " pass
	export GPG_PASS=$pass
fi

echo
echo "Decrypting wallet..."
./gpg-expect.sh	
export GPG_PASS=
echo "Done."
echo

echo "Reseeding wallet..."
electrum -w vault.dat reseed
echo "Done."
echo

echo "Creating transaction..."
electrum -w vault.dat mktx $btc_address $amount > tx.dat
echo "Done."
echo


echo "Your transaction is in the file tx.dat. Copy it to your online computer and run the command: "
echo "electrum sendtx `cat tx.dat`"
echo
echo "Alternatively, you can paste the contents of the file to a site such as bitsend.rowit.co.uk or brainwallet.org, and send it from there."
echo