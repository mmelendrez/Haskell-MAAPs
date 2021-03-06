import Test.Framework (defaultMain, testGroup)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.QuickCheck
import Lib
import Control.Monad (replicateM)
import Data.List (findIndex)
import Data.Maybe (fromMaybe, isJust)
import Data.Char (toUpper, toLower)
import Safe (atMay)
import Types
import Lib

main :: IO ()
main = defaultMain tests

instance Arbitrary Codon where -- this codon is not degenerate!
  arbitrary = Codon <$> (replicateM 3 $ elements validBases) -- list of size 3
  
validBases = upper ++ map toLower upper
  where upper = ("ACGTN-" ++ ambigNts)

newtype ValidSequence = VS String
instance Arbitrary ValidSequence where
  arbitrary = do
    n <- choose (1, 99)
    codons <- replicateM n (arbitrary :: Gen Codon)
    return $ VS $ concatMap (\(Codon x) -> x) codons
    
newtype FrameShiftedSequence = FS String
instance Arbitrary FrameShiftedSequence where
  arbitrary = do
    (VS s) <- arbitrary
    n <- choose (1, 2) 
    -- want our result not to be a factor of 3
    mul <- suchThat (choose (1, 99)) (\x -> not $ factor3 (x + n))
    extra <- replicateM (n * mul) $ elements validBases
    return $ FS (s ++ extra)
    
factor3 x = (x `mod` 3) == 0 
    
tests = [testGroup "Examples!" [
                testProperty "example ATR" prop_example_expand
           ]
       , testGroup "Edge Cases" [
                testProperty "Lower case equivalent ot upper case" prop_lower_case_equivalent_upper
           ]
        ]
  
--prop_ns_are_reported :: ValidSequence  -> Bool
--prop_ns_are_reported (VS s) = fromMaybe False $ do
--  actual <- runWhere (== 'N') s
--  return $ case actual of
--            (WithN _ i') -> True
--            _       -> False
--  
--prop_gaps_are_reported :: ValidSequence  -> Bool
--prop_gaps_are_reported (VS s) = fromMaybe False $ do
--  actual <- runWhere (== '-') s
--  return $ case actual of
--             (Insert _ i') -> True
--             _             -> False
--             
--fromEither :: b -> Either a b -> b
--fromEither = foldr const
--
--prop_frameshifts_are_reported :: FrameShiftedSequence  -> Bool
--prop_frameshifts_are_reported (FS s) = fromMaybe False $ do
--  rows <- getDegens s
--  let actual = last rows
--  let offBy = (length s) `mod` 3
--  return $ actual == (FrameShift (length s) - offBy)

--findIndex on the triples instead; then check the length (1 == synonymous, >1 non-synonymous) and check if it translates to the stop codon.
prop_stop_codon_reported :: ValidSequence -> Bool
prop_stop_codon_reported s = undefined
prop_synonymous_reported :: ValidSequence -> Bool
prop_synonymous_reported s = undefined
prop_non_synonymous_reported :: ValidSequence -> Bool
prop_non_synonymous_reported s = undefined

toMaybe :: Either a b -> Maybe b
toMaybe = foldr (const . Just) Nothing 

runWhere :: (Char -> Bool) -> String -> Maybe Degen
runWhere f s = do
  cdnI <- (`div` 3) <$> i
  results <- toMaybe $ getDegens s
  actual <- (results `atMay` cdnI) :: Maybe Degen
  return actual
  where
    i = findIndex f s
  
prop_ns_are_toGened :: Codon -> Index -> [AA] -> Property
prop_ns_are_toGened c@(Codon nts) i aas = ('N' `elem` nts) ==> (toDegen c aas i) === (WithN c i)
  
prop_gaps_are_toGened :: Codon -> Index -> [AA] -> Property
prop_gaps_are_toGened c@(Codon nts) i aas = ('-' `elem` nts) ==> (toDegen c aas i) === (Insert c i)

prop_stop_codons_are_toGened :: Codon -> Index -> Property
prop_stop_codons_are_toGened c@(Codon nts) i = (toDegen c [Z] i) === (StopCodon Z i c []) -- what are the indices going to be?

-- this test shouldn't care about the order of the amino acids
prop_example_expand = expand "ATR" === Right [(Codon "ATR", [M,I])]

prop_lower_case_equivalent_upper (Codon x) = (expand $ map toLower x) === (expand $ map toUpper x)
        
prop_bad_nts_fail = expand "zzz" === Left "Bases in codon position 1, zzz not found."

--bad_char_count_fails x = expand x == Nothing
--  where types = (x :: String) suchThat (((length x) `mod` 3) /= 0)

--someFunc = do
--  print $ expand  "ATR" -- "Isoleucine", -- "Methionine Start",
--  --B.putStrLn $ fromMaybe (error "Error!") $ process "ATR"
--  --either error print $ process "ATR"
--  print $ expand  "ATC"  -- returns its normal AA (synonymous, without degen)
--  print $ expand  "zzz"  -- Nothing, not in `degen` list
--  print $ expand  "ATRYCSA"  -- Nothing, not divisible by 3
