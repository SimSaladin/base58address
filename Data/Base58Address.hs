{-# LANGUAGE CPP #-}
#ifdef TESTS
module Data.Base58Address (BitcoinAddress, RippleAddress, RippleAddress0(..)) where
#else
module Data.Base58Address (BitcoinAddress, bitcoinAddressPayload, RippleAddress, rippleAddressPayload) where
#endif

import Control.Monad (guard)
import Control.Arrow ((***))
import Data.Word
import Data.Binary (Binary(..), putWord8)
import Data.Binary.Get (getByteString)
import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString as BS

import Data.Base58Address.BaseConvert
import Data.Base58Address.Alphabet

#ifdef TESTS
import Test.QuickCheck

instance Arbitrary Base58Address where
	arbitrary = do
		ver <- arbitrary
		Positive adr <- arbitrary
		let bsiz = length (toBase 256 adr)
		plen <- choose (bsiz,bsiz+100)
		return $ Base58Address ver adr plen

instance Arbitrary BitcoinAddress where
	arbitrary = fmap BitcoinAddress arbitrary

instance Arbitrary RippleAddress where
	arbitrary = fmap RippleAddress arbitrary

newtype RippleAddress0 = RippleAddress0 RippleAddress
	deriving (Show)

instance Arbitrary RippleAddress0 where
	arbitrary = do
		adr <- arbitrary `suchThat` (>=0)
		return $ RippleAddress0 $ RippleAddress $ Base58Address 0 adr 20
#endif

newtype BitcoinAddress = BitcoinAddress Base58Address
	deriving (Ord, Eq)

bitcoinAlphabet :: Alphabet
bitcoinAlphabet = read "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

bitcoinAddressPayload :: BitcoinAddress -> Integer
bitcoinAddressPayload (BitcoinAddress (Base58Address _ p _)) = p

instance Show BitcoinAddress where
	show (BitcoinAddress adr) = showB58 bitcoinAlphabet adr

instance Read BitcoinAddress where
	readsPrec _ s = case decodeB58 bitcoinAlphabet s of
		Just x -> [(BitcoinAddress x,"")]
		Nothing -> []

newtype RippleAddress = RippleAddress Base58Address
	deriving (Ord, Eq)

rippleAlphabet :: Alphabet
rippleAlphabet = read "rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz"

rippleAddressPayload :: RippleAddress -> Integer
rippleAddressPayload (RippleAddress (Base58Address _ p _)) = p

instance Show RippleAddress where
	show (RippleAddress adr) = showB58 rippleAlphabet adr

instance Read RippleAddress where
	readsPrec _ s = case decodeB58 rippleAlphabet s of
		Just x -> [(RippleAddress x,"")]
		Nothing -> []

instance Binary RippleAddress where
	get = do
		value <- (fromBase 256 . BS.unpack) `fmap` getByteString 20
		return $ RippleAddress (Base58Address 0 value 20)

	put (RippleAddress (Base58Address 0 value 20)) = do
		let bytes = toBase 256 value
		mapM_ putWord8 (replicate (20 - length bytes) 0 ++ bytes)
	put _ = error "RippleAddress account ID is always 0, length always 20"

-- Version, payload, payload bytesize
data Base58Address = Base58Address !Word8 !Integer !Int
	deriving (Show, Ord, Eq)

showB58 :: Alphabet -> Base58Address -> String
showB58 alphabet (Base58Address version addr plen) = prefix ++
	toString alphabet 58 (fromBase 256 (bytes ++ mkChk bytes) :: Integer)
	where
	prefix = replicate (length $ takeWhile (==0) bytes) z
	bytes = version : replicate (plen - length bytes') 0 ++ bytes'
	bytes' = toBase 256 addr
	Just z = toAlphaDigit alphabet 0

decodeB58 :: Alphabet -> String -> Maybe Base58Address
decodeB58 alphabet s = do
	(zs,digits) <- fmap (span (==0)) (toDigits alphabet s)
	let (chk,bytes) = splitChk $ toBase 256 $ fromBase 58 digits
	case map fromIntegral zs ++ bytes of
		[] -> Nothing
		(version:bytes') -> do
			guard (mkChk (version:bytes') == chk)
			return $! Base58Address version (fromBase 256 bytes') (length bytes')

splitChk :: [a] -> ([a], [a])
splitChk = (reverse *** reverse) . splitAt 4 . reverse

mkChk :: [Word8] -> [Word8]
mkChk = BS.unpack . BS.take 4 . SHA256.hash . SHA256.hash . BS.pack
