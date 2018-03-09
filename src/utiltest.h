// Copyright (c) 2016 The edash developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include "wallet/wallet.h"
#include "edash/JoinSplit.hpp"
#include "edash/Note.hpp"
#include "edash/NoteEncryption.hpp"

CWalletTx GetValidReceive(ZCJoinSplit& params,
                          const libedash::SpendingKey& sk, CAmount value,
                          bool randomInputs);
libedash::Note GetNote(ZCJoinSplit& params,
                       const libedash::SpendingKey& sk,
                       const CTransaction& tx, size_t js, size_t n);
CWalletTx GetValidSpend(ZCJoinSplit& params,
                        const libedash::SpendingKey& sk,
                        const libedash::Note& note, CAmount value);
