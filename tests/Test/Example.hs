{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Test.Example where

import NFT.OffChain
import Account.Safe.OffChain
import Contract.Accuse
import Contract.Create
import Contract.Safe.OffChain
import Contract.Sign
import Contract.Mediate
import Control.Monad (void)
import Control.Monad.Freer.Extras as Extras (logError, logInfo)
import Data.Default (Default (..))
import qualified Data.Map as Map
import Data.Monoid (Last (..))
import Data.Text (Text, pack)
import Ledger
import Ledger.Value
import Plutus.Contract.Test (Wallet (Wallet), knownWallet, mockWalletPaymentPubKey)
import Plutus.Trace.Emulator as Emulator
import PlutusTx.AssocMap as PlutusMap
import PlutusTx.Prelude
  ( Bool (..),
    BuiltinByteString,
    Either (Left),
    Integer,
    Maybe (Just, Nothing),
    Semigroup ((<>)),
    ($),
    (++),
    (-),
  )
import Test.Sample
import Test.Trace
import Prelude (IO, Show (..), String, return, error)

mintNFTExample :: EmulatorTrace ()
mintNFTExample = do
  let alice :: Wallet
      alice = knownWallet 1

  aHdr <- activateContractWallet alice nftEndpoints

  mintNFTTrace aHdr 16

  void $ Emulator.waitNSlots 1

createAccountExample :: EmulatorTrace ()
createAccountExample = do
  let alice :: Wallet
      alice = knownWallet 1

      tkts :: [CurrencySymbol]
      tkts = [(createContractCurrencySymbol sampleContractSettings)]

  aHdr <- activateContractWallet alice accountEndpoints

  createAccountTrace aHdr (sampleAccountSettings tkts)

  void $ Emulator.waitNSlots 1

createContractExample :: EmulatorTrace ()
createContractExample = do
  let alice, judge :: Wallet
      alice = knownWallet 1
      judge = knownWallet 7

      tkts :: [CurrencySymbol]
      tkts =
        [(createContractCurrencySymbol sampleContractSettings)]

  createAccountExample

  aHdr <- activateContractWallet alice contractEndpoints

  mNft <-
    createContractTrace
      aHdr
      (sampleAccountSettings tkts)
      sampleContractSettings
      ( sampleContractCore
          (unPaymentPubKeyHash $ paymentPubKeyHash $ mockWalletPaymentPubKey alice)
          10_000_000
          [pubKeyHashAddress (paymentPubKeyHash $ mockWalletPaymentPubKey judge) Nothing]
          []
      )

  void $ Emulator.waitNSlots 1

signContractExample :: EmulatorTrace ()
signContractExample = do
  let alice, bob, judge :: Wallet
      alice = knownWallet 1
      bob = knownWallet 2
      judge = knownWallet 7

      tkts :: [CurrencySymbol]
      tkts =
        [ (createContractCurrencySymbol sampleContractSettings),
          (signContractCurrencySymbol sampleContractSettings)
        ]

  aHdr <- activateContractWallet alice accountEndpoints
  bHdr <- activateContractWallet bob accountEndpoints

  createAccountTrace aHdr (sampleAccountSettings tkts)
  createAccountTrace bHdr (sampleAccountSettings tkts)

  void $ Emulator.waitNSlots 1

  aCHdr <- activateContractWallet alice contractEndpoints
  bCHdr <- activateContractWallet bob contractEndpoints

  mNft <-
    createContractTrace
      aCHdr
      (sampleAccountSettings tkts)
      sampleContractSettings
      ( sampleContractCore
          (unPaymentPubKeyHash $ paymentPubKeyHash $ mockWalletPaymentPubKey alice)
          10_000_000
          [pubKeyHashAddress (paymentPubKeyHash $ mockWalletPaymentPubKey judge) Nothing]
          tkts
      )

  void $ Emulator.waitNSlots 1

  case mNft of
    Nothing -> error "Sign contract error: contract not found"
    Just nft -> do
      signContractTrace
        bCHdr
        (sampleAccountSettings tkts)
        sampleContractSettings
        0
        nft

      void $ Emulator.waitNSlots 1


raiseDisputeExample :: EmulatorTrace ()
raiseDisputeExample = do
  let alice, bob, judge :: Wallet
      alice = knownWallet 1
      bob = knownWallet 2
      judge = knownWallet 7

      tkts :: [CurrencySymbol]
      tkts =
        [ (createContractCurrencySymbol sampleContractSettings),
          (signContractCurrencySymbol sampleContractSettings),
          (raiseDisputeCurrencySymbol sampleContractSettings)
        ]

  alcAccHnd <- activateContractWallet alice accountEndpoints
  bobAccHnd <- activateContractWallet bob accountEndpoints

  createAccountTrace alcAccHnd (sampleAccountSettings tkts)
  createAccountTrace bobAccHnd (sampleAccountSettings tkts)

  void $ Emulator.waitNSlots 1

  alcCtrHnd <- activateContractWallet alice contractEndpoints
  bobCtrHnd <- activateContractWallet bob contractEndpoints

  mNft <-
    createContractTrace
      alcCtrHnd
      (sampleAccountSettings tkts)
      sampleContractSettings
      ( sampleContractCore
          (unPaymentPubKeyHash $ paymentPubKeyHash $ mockWalletPaymentPubKey alice)
          10_000_000
          [pubKeyHashAddress (paymentPubKeyHash $ mockWalletPaymentPubKey judge) Nothing]
          tkts
      )

  void $ Emulator.waitNSlots 1

  case mNft of
    Nothing -> Extras.logError @String "Sign contract error: contract not found"
    Just nft -> do
      signContractTrace
        bobCtrHnd
        (sampleAccountSettings tkts)
        sampleContractSettings
        0
        nft

      void $ Emulator.waitNSlots 1

      raiseDisputeTrace
        alcCtrHnd
        sampleContractSettings
        (unPaymentPubKeyHash $ paymentPubKeyHash $ mockWalletPaymentPubKey bob)
        5
        nft

      void $ Emulator.waitNSlots 1

resolveDisputeExample :: EmulatorTrace ()
resolveDisputeExample = do
  let alice, bob, judge :: Wallet
      alice = knownWallet 1
      bob = knownWallet 2
      judge = knownWallet 7

      tkts :: [CurrencySymbol]
      tkts =
        [ (createContractCurrencySymbol sampleContractSettings),
          (signContractCurrencySymbol sampleContractSettings),
          (raiseDisputeCurrencySymbol sampleContractSettings),
          (resolveDisputeCurrencySymbol sampleContractSettings)
        ]

  alcAccHnd <- activateContractWallet alice accountEndpoints
  bobAccHnd <- activateContractWallet bob accountEndpoints

  createAccountTrace alcAccHnd (sampleAccountSettings tkts)
  createAccountTrace bobAccHnd (sampleAccountSettings tkts)

  void $ Emulator.waitNSlots 1

  alcCtrHnd <- activateContractWallet alice contractEndpoints
  bobCtrHnd <- activateContractWallet bob contractEndpoints
  jdgCtrHnd <- activateContractWallet judge contractEndpoints

  mNft <-
    createContractTrace
      alcCtrHnd
      (sampleAccountSettings tkts)
      sampleContractSettings
      ( sampleContractCore
          (unPaymentPubKeyHash $ paymentPubKeyHash $ mockWalletPaymentPubKey alice)
          10_000_000
          [pubKeyHashAddress (paymentPubKeyHash $ mockWalletPaymentPubKey judge) Nothing]
          tkts
      )

  void $ Emulator.waitNSlots 1

  case mNft of
    Nothing -> Extras.logError @String "Sign contract error: contract not found"
    Just nft -> do
      signContractTrace
        bobCtrHnd
        (sampleAccountSettings tkts)
        sampleContractSettings
        0
        nft

      void $ Emulator.waitNSlots 1

      raiseDisputeTrace
        alcCtrHnd
        sampleContractSettings
        (unPaymentPubKeyHash $ paymentPubKeyHash $ mockWalletPaymentPubKey bob)
        50
        nft

      void $ Emulator.waitNSlots 1

      resolveDisputeTrace
        jdgCtrHnd
        sampleContractSettings
        resolution
        nft

      void $ Emulator.waitNSlots 1
