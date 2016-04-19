{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
module Lib where
import qualified Data.HashMap.Strict as H
import Data.Hashable 
import Data.Maybe (fromMaybe)
import Data.List (unfoldr, splitAt, findIndices, intersperse, intercalate, intersect)
import GHC.Generics
import Data.Char (ord)
import Data.Csv hiding (lookup)
import Data.Text (Text, pack)
import Control.Monad (forM_, zipWithM_)
import qualified Data.ByteString.Lazy as B
import qualified Data.ByteString.Lazy.Char8 as C
--import Bio.Sequence.Fasta (readFasta, toStr, seqdata, seqid)
import Bio.Sequence.Fasta 
import Bio.Core.Sequence
import Options.Generic 
import Types

{-
TODO: Fix formatting somehow
TODO: Report fasta IDs somehow
TODO: More tests better
TODO: CI
X TODO: Convert maybes to Either with error descriptions
X TODO: Row should not be stringly typed

 Post-processing
 * note stop codons
 check frame shifts (length check)


 this should also report position of degenerate NT (could be done after return) -- do this by just keeping the triple as you go. AA position is just its index
 Should check if synonymous -- do this by checking size of AA list
 report inserts, Ns

 in order to do this need AAs, triples (codons), index
 case on info to get Degen; case on Degen to get Report
 frame shift should be handled seperately
 (but a frame shift is likely to be noticed sooner, and needs to be handled explicitly
 before / within `expand`, because we will get a triple of size 1 or 2.
 Not sure how to handle frame shifts within polypeptide, because there are no stop codons to go off of.
 | NT pos | NTs | AAs   | AAposition | Type |
 | 9      | AKK | R/Z/Z |    3       | Non-synonymous |
 | 4      | ANA |  *    |    *       | N     |
 | 4      | A-A |  *    |    *       | Gap |
 | 4      | ATA |  A    |    2       | Stop Codon|
 | 4      | ATA |  A    |    2       | Stop Codon|
 how handle a *possible* stop codon?
 should codons with multiple degens output NT degen indices?
-}

type Error = String


run :: Options -> IO ()
run opts = do
  recs <- readFasta (unHelpful $ fasta opts)
  forM_ recs printOne
  where
    printOne x = either putStrLn (`forM_` C.putStrLn) $ process x
    
filterDegens :: [Degen] -> [Degen]
filterDegens xs = filter (not . isNormal) $ dropStopCodon $ xs
  where
    isNormal NormalCodon = True
    isNormal _           = False
    dropStopCodon ((StopCodon _ _ _ _ ):[]) = []
    dropStopCodon (x:xs)                    = x : dropStopCodon xs

process :: Sequence -> (Either Error [B.ByteString])
process s@(Seq _ (SeqData {unSD=seq}) _ ) = do
  xs <- filterDegens <$> getDegens seq'
  let rows = map (record . toList . (fieldList id')) xs
  return $ [header', "\n", (encodeWith outOptions rows)]
  where
    -- this gives the sequence ID as the first characters before any space.
    id' = Id $ C.unpack $ unSL $ seqid s
    seq' =  C.unpack seq
    outOptions = defaultEncodeOptions {encDelimiter = fromIntegral (ord '\t')} 
    header' = B.intercalate "\t" $ toList fields
    
toDegen :: Codon -> [AA] -> Index -> Degen
toDegen cdn@(Codon nts) aas i
  | '-' `elem` nts = Insert cdn i
  | 'N' `elem` nts = WithN  cdn i
  | otherwise = case aas of
       ([])  ->   FrameShift    i 
       (Z:[])  -> StopCodon     Z   i cdn  ntIdxs
       (aa:[]) -> if (not $ doIntersect nts ambigNts) then NormalCodon else Synonymous    aa  i cdn  ntIdxs
       aas   ->   NonSynonymous aas i cdn  ntIdxs
  where
    ntIdxs = map (\n -> ((i - 1) * 3) + 1 + n) $ findIndices (`elem` ambigNts) nts

getDegens :: String -> Either Error [Degen] 
getDegens s = do
  (cds, aas) <- unzip <$> expand s
  --let ambigs = filter (\((Codon s), _, _) -> doIntersect s ambigNts) $ zip3 cds aas [1..]
  --return $ map  (uncurry3 toDegen) ambigs
  return $ zipWith3 toDegen cds aas [1..]
  where uncurry3 f = \(x, y, z) -> f x y z
  
doIntersect x y = not $ null $ intersect x y
expand :: String -> Either Error [(Codon, [AA])] 
expand xs = (zip codons) <$> expandeds
  where
    codons = map Codon $ takeWhile (not . null) $ unfoldr (Just . (splitAt 3)) xs
    expandeds = sequence $ zipWith tryExpand [1..] codons
    tryExpand i cdn@(Codon x) = if (not $ null $ intersect x "-N") then Right [] else expandTriple i  cdn 
    
toEither :: b -> Maybe a -> Either b a
toEither b a = maybe (Left b) Right a
-- toEither msg ma = foldr (const . Right) (Left msg) ma

expandTriple :: Int -> Codon -> Either Error [AA] -- change to Either
expandTriple i (Codon xs) = do
    degens' <- toEither ("Bases in codon position " ++ show i ++ ", " ++ xs ++ " not found.") $ lookups allBases xs
    let perms = map Codon $ sequence degens'
    aas' <- toEither ("Permutation AA lookup in codon position " ++ show i ++ ", " ++ xs ++ " not found.") $ lookups codonTable perms
    return aas'
 where
  lookups m xs' = sequence $ map (`H.lookup` m) xs' 
  allBases :: H.HashMap Char String
  allBases = H.fromList (ambig ++ nonAmbig ++ otherBases)
    where
      nonAmbig   = zipString "ACTG"
      otherBases = zipString "N-"
      ambigExp   = ["AG", "GC", "TG", "ACG", "CGT", "CT", "AT", "CA", "ACT"]
      ambig      = zip ambigNts ambigExp
      zipString :: String -> [(Char, String)]
      zipString xs = zip xs $ map (:[]) xs
    
codonTable :: CodonTable
codonTable = H.fromList $ zip codons aas
  where 
    codons = map Codon $ sequence $ replicate 3 "ACGT" 
    aas = map char2AA ("KNKNTTTTRSRSIIMIQHQHPPPPRRRRLLLLEDEDAAAAGGGGVVVVZYZYSSSSZCWCLFLF" :: String)
    char2AA x = fromMaybe (error ("Bad AA " ++ show x) ) $ lookup x (zip (map (head . show) [K ..] ) [K ..])

ambigNts = ['M' , 'R' , 'W' , 'S' , 'Y' , 'K' , 'V' , 'H' , 'D' , 'B']
-- (length aas, length codons) -- these need to be equal 
