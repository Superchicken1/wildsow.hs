module Model.Bots where

import Model.Model as Model
import Model.Updates
import Data.List
import System.Random
import System.Random.Shuffle
import Model.Validation
import System.Random.Shuffle
import Data.Function (on)
import Data.Maybe

-- Spieltheorie
-- bei Poker um ein dynamisches Spiel mit unvollkommener Informationen und Zufallsereignissen. Poker ist dabei ein
-- strikt kompetatives Nullsummenspiel (einer gewinnt, alle anderen verlieren) und nicht symmetrisch,
-- da die zu wählenden Handlungsalternativen von der Position am Tisch abhängen.
-- fast so wie Wildsow...
-- Pokerspiel um ein unvollkommenes dynamisches Nullsummenspiel mit Zufallseinfluß

-- check if its a turn for a bot and do it
botMove :: GameState -> Maybe PlayerMove
botMove gs@GameState {playerStates = playersStates, phase=phase}
    | (isWaitingForCards phase || isWaitingForTricks phase) =
        case currentPlayer of
            RandomBot _ -> Just $ randomBotMove gs currentPlayerState
            SmartBot _ -> Just $ smartBotMove gs currentPlayerState
            HumanPlayer _ -> Nothing
    | otherwise = Nothing
    where
        currentPlayerState = head playersStates
        currentPlayer = player currentPlayerState


-- RandomBot
randomBotMove :: GameState -> PlayerState -> PlayerMove
randomBotMove gs@GameState {phase = WaitingForTricks p} me = randomBotTricksToMake gs me
randomBotMove gs@GameState {phase = WaitingForCard p} me = randomBotCardToPlay gs me
randomBotMove gs me = randomBotCardToPlay gs me

randomBotTricksToMake :: GameState -> PlayerState -> PlayerMove
randomBotTricksToMake gs@GameState{playerStates = players, stdGen=gen} PlayerState{hand=hand, player=me} =
    let (rand, _) = randomR (0,length hand) gen
        amountOfPlayers = length players
    in TellNumberOfTricks me rand

randomBotCardToPlay :: GameState -> PlayerState -> PlayerMove
randomBotCardToPlay gs@GameState { trump=trump, currentColor=currentColor, stdGen=gen} PlayerState{hand=hand, player=me} =
    case currentColor of
        Nothing -> PlayCard me (randomCard hand gen)
        Just currentColor' -> PlayCard me (randomCard (playeableCards2 trump currentColor' hand) gen)

{-
SmartBot
smart tricks
play highest cards until tricks reached, then play lowest cards
play highest card if it is possible to win else lowest card
-}
smartBotMove :: GameState -> PlayerState -> PlayerMove
smartBotMove gs@GameState {phase = WaitingForTricks p} me = smartBotTricksToMake gs me
smartBotMove gs@GameState {phase = WaitingForCard p} me = smartBotCardToPlay gs me

smartBotTricksToMake :: GameState -> PlayerState -> PlayerMove
smartBotTricksToMake gs ps@PlayerState{hand=hand, player=me} =
    let chances = map (\card -> cardWinningChance gs ps card) hand
        chancesAvg =  (sum chances) / (genericLength chances)
        predictedTricks = round (chancesAvg * genericLength hand / genericLength (playerStates gs))
    in TellNumberOfTricks me predictedTricks

--
smartBotCardToPlay :: GameState -> PlayerState -> PlayerMove
smartBotCardToPlay gs@GameState { trump=trump, currentColor=currentColor, stdGen=gen} ps@PlayerState{hand=hand, player=me} =
    case currentColor of
        -- set the color
        Nothing -> if belowTricks gs ps
            then PlayCard me $ fst $ head $ sortedHighestHandCards gs ps -- play highest card
            else PlayCard me $ fst $ last $ sortedHighestHandCards gs ps-- play lowest card
        -- play a card
        Just currentColor -> PlayCard me (randomCard (playeableCards2 trump currentColor hand) gen)

------- Helpers
belowTricks :: GameState -> PlayerState -> Bool
belowTricks GameState{currentRound=currentRound} ps@PlayerState{tricks=tricks, tricksSubround=tricksSubround} =
    let toldTricksThisRound = head tricks
        tricksInThisRound = foldl (\a (_,s) -> a+s) 0 (filter (\(r,_) -> currentRound == r) tricksSubround)
    in toldTricksThisRound < tricksInThisRound

sortedHighestHandCards:: GameState -> PlayerState -> [(Card, Double)]
sortedHighestHandCards gs ps@PlayerState{hand=hand} =
    let zipped = zip (hand) (map (cardWinningChance gs ps) hand)
    in sortBy (flip compare `on` snd) zipped

-- cardWinningChance
cardWinningChance :: GameState -> PlayerState -> Card -> Double
-- with no color -> tell color
cardWinningChance gs@GameState{pile=pile, playerStates=playersStates, currentColor=Nothing} playerState card@Card{value=v, color=c} =
    let
      lengthPossibleHigherCards = genericLength (possibleHigherCards gs{currentColor=Just c} playerState card) -- chance if card is played -> so set currentColor!
      lengthUnknownCards = genericLength (unknownCards gs playerState)
      lengthPile = genericLength pile
      lengthCurrentCards = genericLength (opponentPlayedCards gs)
    in 1.0 - lengthPossibleHigherCards / (lengthUnknownCards + lengthPile + lengthCurrentCards)

-- with current color
cardWinningChance gs@GameState{pile=pile, playerStates=playersStates, currentColor=Just currentColor, trump=trump} playerState card@Card{value=v, color=c}
    -- no chance to win against first currentCard
    | c/= currentColor && c/=trump = 0.0
    | otherwise = 1.0 - lengthPossibleHigherCards / (lengthUnknownCards + lengthPile + lengthCurrentCards)
    where
      lengthPossibleHigherCards = genericLength (possibleHigherCards gs playerState card)
      lengthUnknownCards = genericLength (unknownCards gs playerState)
      lengthPile = genericLength pile
      lengthCurrentCards = genericLength (opponentPlayedCards gs)

-- only if the bot has to tell the color
possibleHigherCards :: GameState -> PlayerState -> Card -> Cards
-- with no color -> tell color
possibleHigherCards gs@GameState{currentColor=Nothing, trump=trump, pile=pile} ps@PlayerState{hand=hand} card@Card{value=v, color=c}
    -- higher cards: higher trumps
    | c == trump = filter (\Card{value=v', color=c'} -> v'>v && c'==trump) myUnknownCards -- map (\(value a -> a)) myUnknownCards
    -- higher cards: all same color and trump
    | otherwise  = filter (\Card{value=v', color=c'} -> v'>v && c'==c || c'==trump) myUnknownCards -- map (\(value a -> a)) myUnknownCards
    where myUnknownCards = unknownCards gs ps

-- with current color
possibleHigherCards gs@GameState{currentColor=Just currentColor, trump=trump} ps@PlayerState{hand=hand} card@Card{value=v, color=c}
    -- higher cards: higher trumps
    | currentColor==c && trump==c   = filter (\Card{value=v', color=c'} -> v'>v && c'==trump) myUnknownCards
    | currentColor/=c && trump==c   = filter (\Card{value=v', color=c'} -> v'>v && c'==trump) myUnknownCards
    -- higher cards: trumps and higher currentColor
    | currentColor==c && trump/=c   = filter (\Card{value=v', color=c'} -> c'==trump || c'==currentColor && v'>v) myUnknownCards
    -- higher cards: all others
    | currentColor/=c && trump/=c   = filter (\Card{value=v', color=c'} -> c'==trump || c'==currentColor) myUnknownCards
    | otherwise                     = myUnknownCards
    where
        myUnknownCards    = unknownCards gs ps

-- cards that are possible in the opponents hands
unknownCards :: GameState -> PlayerState -> Cards
unknownCards gs@GameState{pile=pile} ps@PlayerState{hand=hand} = ((deck \\ pile) \\ hand ) \\ opponentPlayedCards gs
-- unknownCards gs@GameState{pile=pile} ps@PlayerState{hand=hand} = map (\\) [deck, pile, hand, opponentPlayedCards gs]

-- cards the opponent played before my turn
opponentPlayedCards :: GameState -> Cards
opponentPlayedCards gs@GameState{playerStates=playerStates} = catMaybes $ map (playedCard) playerStates

-- playable cards
playeableCards2 :: Color -> Color -> Cards -> Cards
playeableCards2 trump currentColor hand
    | length cardsFitCurrentColor > 0 = cardsFitCurrentColor
    | length cardsFitTrump > 0 = cardsFitTrump
    | otherwise = hand
    where
        cardsFitCurrentColor = filter (\Card{value=v', color=c'} ->  c' == currentColor) hand
        cardsFitTrump        = filter (\Card{value=v', color=c'} ->  c' == trump) hand

randomCard :: Cards -> StdGen -> Card
randomCard cards gen =
    let (rand, _) = randomR (0, (length cards)-1) gen
        shuffled = shuffle' cards (length cards) gen
    in head shuffled

aTest :: Int -> Int
aTest a = a + 1