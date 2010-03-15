module Main (cgiMain, cliMain, main) where

import Control.Applicative
import Control.Concurrent
import Control.Exception
import Control.Monad
import Data.Char
import Language.Haskell.Exts
import Numeric
import Prelude hiding (catch)
import Stepeval
import System.Environment
import System.IO

main :: IO ()
main = do
 e <- lookup "QUERY_STRING" <$> getEnvironment
 case e of
  Nothing -> cliMain
  Just s -> cgiMain s

cliMain :: IO ()
cliMain = do
 putStrLn "Enter a string to parse, terminated by a blank line:"
 exp <- unlines <$> getLines
 case parseExp exp of
  ParseOk e -> forM_ (itereval e) $
   (>> (hFlush stdout >> getLine)) . putStr . prettyPrint
  ParseFailed _ _ -> putStrLn "Sorry, parsing failed."
 where getLines :: IO [String]
       getLines = do
        line <- getLine
        if null line then return [] else (line :) <$> getLines

cgiMain :: String -> IO ()
cgiMain qstr = do
 let exp = case dropWhile (/= '=') qstr of
      _ : v -> unescape v
      "" -> ""
 putStrLn . concat $
  ["Content-Type: text/html; charset=UTF-8\n\n",
   "<html>\n<head>\n",
   "<title>Step-by-step evaluator</title>\n",
   "<style type=\"text/css\">\n",
   "ol { white-space: pre; font-family: monospace }\n</style>\n",
   "</head>\n",
   "<body>\n<form method=\"get\" action=\"\">\n",
   "<textarea rows=\"5\" cols=\"80\" name=\"expr\">",
   exp,
   "</textarea><br>\n",
   "<input type=\"submit\" value=\"Evaluate!\">\n",
   "</form>\n"]
 myThreadId >>= forkIO . (threadDelay 250000 >>) . killThread
 unless (null exp) $ case parseExp exp of
  ParseOk e -> putStrLn (pp e) `catches`
   [Handler $ \e -> print (e :: ErrorCall),
    Handler $ \e -> const (putStrLn "Time limit expired!")
     (e :: AsyncException)]
  ParseFailed _ _ -> putStrLn "Sorry, parsing failed."
 putStrLn "\n</body>\n</html>"
 where unescape ('+':cs) = ' ':unescape cs
       unescape ('%':a:b:cs) = case readHex [a, b] of
        [(x, "")] -> chr x : unescape cs
        _ -> error $ "Failed to parse percent escape: " ++ [a, b]
       unescape (c:cs) = c:unescape cs
       unescape [] = ""
       pp e = "<ol>" ++ concatMap (("<li>" ++) . (++ "</li>\n") .
        prettyPrint) (itereval e)

