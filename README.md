# Cross-Chain Rebase Token

[![CI](https://github.com/tohidul3417/ccip-rebase-token/actions/workflows/test.yml/badge.svg)](https://github.com/tohidul3417/ccip-rebase-token/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Foundry-based implementation of a cross-chain, interest-bearing rebase token. This project utilizes Chainlink CCIP to enable the bridging of tokens between chains while preserving a user's unique, locked-in interest rate.

The core economic model rewards early adoption by offering a global interest rate that only decreases over time for new depositors. This repository serves as a learning exercise and was completed as a part of the **Advanced Foundry** course's (offered by Cyfrin Updraft) *Cross Chain Rebase Token* section.
---

## Architecture

The protocol consists of three main contracts that work in concert with Chainlink CCIP infrastructure.

* **`RebaseToken.sol`**: An ERC20 token with custom rebasing logic that assigns a persistent interest rate to each user upon their last state-changing interaction (deposit, transfer, bridge).
* **`Vault.sol`**: The primary entry point for users to deposit ETH and mint `RebaseToken`s at the current global interest rate.
* **`RebaseTokenPool.sol`**: The CCIP gateway that handles the burning of tokens on the source chain and minting on the destination chain, carrying the user's specific interest rate across in the CCIP message.

## Getting Started

### Prerequisites

  * [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  * [Foundry](https://getfoundry.sh/)

### Installation

1.  **Clone the repository** (including submodules):

    ```bash
    git clone --recurse-submodules [https://github.com/tohidul3417/ccip-rebase-token.git](https://github.com/tohidul3417/ccip-rebase-token.git)
    cd ccip-rebase-token
    ```

2.  **Install dependencies**:

    ```bash
    forge install
    ```

3.  **Build the project**:

    ```bash
    forge build
    ```

4.  **Set up environment variables**:
    Create a file named `.env` in the root of the project. This file will hold your RPC URLs.

    ```bash
    touch .env
    ```

    Add the following variables to your new `.env` file, replacing the placeholder values with your own:

    ```
    SEPOLIA_RPC_URL="YOUR_SEPOLIA_RPC_URL"
    ARBITRUM_SEPOLIA_RPC_URL="YOUR_ARBITRUM_SEPOLIA_RPC_URL"
    ```

-----

### ⚠️ Advanced Security: The Professional Workflow for Key Management

Storing a plain-text `PRIVATE_KEY` in a `.env` file is a significant security risk. If that file is ever accidentally committed to GitHub, shared, or compromised, any funds associated with that key will be stolen instantly.

The professional standard is to **never store a private key in plain text**. Instead, we use Foundry's built-in **keystore** functionality, which encrypts your key with a password you choose.

Here is the clear, step-by-step process:

#### **Step 1: Create Your Encrypted Keystore**

This command generates a new private key and immediately encrypts it, saving it as a secure JSON file.

1.  **Run the creation command:**

    ```bash
    cast wallet new
    ```

2.  **Enter a strong password:**
    The terminal will prompt you to enter and then confirm a strong password. **This is the only thing that can unlock your key.** Store this password in a secure password manager (like 1Password or Bitwarden).

3.  **Secure the output:**
    The command will output your new wallet's **public address** and the **path** to the encrypted JSON file (usually in `~/.foundry/keystores/`).

      * Save the public address. You will need it to send funds to your new secure wallet.
      * Note the filename of the keystore file.

At this point, your private key exists only in its encrypted form. It is no longer in plain text on your machine.

#### **Step 2: Fund Your New Secure Wallet**

Use a faucet or another wallet to send some testnet ETH and LINK to the new **public address** you just generated.

#### **Step 3: Use Your Keystore Securely for Deployments**

Now, when you need to send a transaction (like deploying a contract), you will tell Foundry to use your encrypted keystore. Your private key is **never** passed through the command line or stored in a file.

1.  **Construct the command:**
    Use the `--keystore` flag to point to your encrypted file and the `--ask-pass` flag to tell Foundry to securely prompt you for your password.

2.  **Example Deployment Command:**

    ```bash
    # This command deploys the Token and Pool on Sepolia
    forge script script/Deployer.s.sol:TokenAndPoolDeployer \
      --rpc-url $SEPOLIA_RPC_URL \
      --keystore ~/.foundry/keystores/UTC--2025-07-27T...--your-wallet-address.json \
      --ask-pass \
      --broadcast
    ```

3.  **Enter your password when prompted:**
    Foundry will pause and securely ask for the password you created in Step 1.

**The Atomic Security Insight:** When you run this command, Foundry reads the encrypted file, asks for your password in memory, uses it to decrypt the private key for the single purpose of signing the transaction, and then immediately discards the decrypted key. The private key never touches your shell history or any unencrypted files. This is a vastly more secure workflow.

-----

## Usage

### Testing

The project includes a comprehensive test suite for both unit and cross-chain integration scenarios.

  * **Run all tests**:
    ```bash
    forge test
    ```
  * **Run a specific test case with the following command**:
    ```bash
    forge test --mt testBridgeAllTokens -vvvv
    ```
  * **Check test coverage**:
    ```bash
    forge coverage
    ```

### Deployment

The `script/` directory contains Foundry scripts for deploying and interacting with the protocol on a live testnet. Refer to the scripts for detailed command examples.

  * `Deployer.s.sol`: Deploys the core contracts (`RebaseToken`, `RebaseTokenPool`, `Vault`).
  * `ConfigurePool.s.sol`: Configures the two-way connection between deployed pools on different chains.
  * `BridgeTokens.s.sol`: A script for users to initiate a cross-chain token transfer.

-----

## ⚠️ Security Disclaimer

This project was built for educational purposes and has **not** been audited. Do not use in a production environment or with real funds. Always conduct a full, professional security audit before deploying any smart contracts.

-----

## License

This project is distributed under the MIT License. See `LICENSE` for more information.
