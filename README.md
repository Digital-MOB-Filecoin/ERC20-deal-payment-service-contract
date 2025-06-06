# Foundry Solidity Project

## Overview
This project is a Solidity-based smart contract application that implements a payment system using the EscrowContract contract. The contract handles payments, settlements, and operator approvals.

## Project Structure
```
foundry-solidity-project
├── src
│   └── EscrowContract.sol          # Contains the EscrowContract contract code
├── test
│   └── EscrowContract.t.sol        # Contains test cases for the EscrowContract contract
├── script
│   └── Deploy.s.sol                # Deployment script for the EscrowContract contract
├── lib                             # Directory for external libraries or dependencies
├── foundry.toml                    # Configuration file for Foundry
└── README.md                       # Documentation for the project
```

## Setup Instructions
1. **Install Foundry**: Follow the instructions on the [Foundry GitHub page](https://github.com/foundry-rs/foundry) to install Foundry.

2. **Clone the Repository**: Clone this repository to your local machine.
   ```
   git clone <repository-url>
   cd foundry-solidity-project
   ```

3. **Install Dependencies**: If there are any dependencies specified in the `foundry.toml` file, run:
   ```
   forge install
   ```

4. **Compile the Contracts**: Compile the Solidity contracts using:
   ```
   forge build
   ```

5. **Run Tests**: Execute the test cases to ensure everything is functioning correctly:
   ```
   forge test
   ```

6. **Deploy the Contract**: Use the deployment script to deploy the EscrowContract contract to a blockchain network:
   ```
   forge script script/Deploy.s.sol --broadcast
   ```

## Usage
- The `EscrowContract.sol` contract allows users to create payment rails, deposit funds, withdraw funds, and manage operator approvals.
- The `EscrowContract.t.sol` file contains various test cases to validate the functionality of the EscrowContract contract.
- The `Deploy.s.sol` script is used to deploy the EscrowContract contract to a specified network.

## License
This project is licensed under the MIT License. See the LICENSE file for more details.