{-| Module: Config
 
Quick and dirty parsing of config files.
-}
{-# LANGUAGE FlexibleContexts #-}
module Config where


import Text.Parsec
import Text.Parsec.Char

data Role = Generator 
          | Normal
          deriving (Show, Eq)

parseRole :: Stream s m Char => ParsecT s u m Role
parseRole =  (string "rng"    *> pure Generator) 
         <|> (string "normal" *> pure Normal   )  

data Config = Config
  { hostname :: String
  , port     :: String
  , role     :: Role
  } 

instance Show Config where
    show (Config h p r) = concat [h, ":",p, " as ", show r]

readConfig :: Stream s m Char => ParsecT s u m Config
readConfig = Config 
          <$> (spaces *> manyTill anyChar space)
          <*> (spaces *> manyTill digit   space)
          <*> (spaces *> parseRole)

readConfigFile :: FilePath -> IO [Config]
readConfigFile fname = do
    input <- lines <$> readFile fname 
    let lineParser str line  = runParser readConfig () (concat [fname,": line ", show line]) str
        e_configs            = zipWith lineParser input [1..]
    mapM_ putStrLn [show err | Left err <- e_configs]
    return [ conf | Right conf <- e_configs]        

       
     

