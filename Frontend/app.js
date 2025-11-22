// EscrowX Frontend using ethers.js
// Make sure to replace contractAddress with your deployed address 
 
const contractAddress = "REPLACE_WITH_DEPLOYED_CONTRACT_ADDRESS";
const contractABI = [
  "function createEscrow(address payable _seller, address _arbiter, uint256 _amount) returns (uint256)",
  "function fundEscrow(uint256 escrowId) payable",
  "function resolveEscrow(uint256 escrowId, bool releaseToSeller)",
  "function getEscrow(uint256 escrowId) view returns (address buyer, address seller, address arbiter, uint256 amount, uint8 status)"
];

let provider, signer, contract;

async function connect() {
  if (!window.ethereum) throw new Error("Please install MetaMask");
  provider = new ethers.providers.Web3Provider(window.ethereum);
  await provider.send("eth_requestAccounts", []);
  signer = provider.getSigner();
  contract = new ethers.Contract(contractAddress, contractABI, signer);
}

// Create escrow
async function createEscrow() {
  try {
    await connect();
    const seller = document.getElementById("seller").value;
    const arbiter = document.getElementById("arbiter").value;
    const amountEth = document.getElementById("amount").value;
    const amountWei = ethers.utils.parseEther(amountEth);

    const tx = await contract.createEscrow(seller, arbiter, amountWei);
    const receipt = await tx.wait();
    document.getElementById("createResult").innerText =
      `Escrow created. Tx: ${receipt.transactionHash}`;
  } catch (err) {
    document.getElementById("createResult").innerText = err.message;
  }
}

// Fund escrow
async function fundEscrow() {
  try {
    await connect();
    const id = document.getElementById("fundEscrowId").value;
    const e = await contract.getEscrow(id);
    const tx = await contract.fundEscrow(id, { value: e[3] });
    const receipt = await tx.wait();
    document.getElementById("fundResult").innerText =
      `Escrow funded. Tx: ${receipt.transactionHash}`;
  } catch (err) {
    document.getElementById("fundResult").innerText = err.message;
  }
}

// Resolve escrow
async function resolveEscrow() {
  try {
    await connect();
    const id = document.getElementById("resolveEscrowId").value;
    const release = document.querySelector('input[name="resolve"]:checked').value === "release";
    const tx = await contract.resolveEscrow(id, release);
    const receipt = await tx.wait();
    document.getElementById("resolveResult").innerText =
      `Escrow resolved. Tx: ${receipt.transactionHash}`;
  } catch (err) {
    document.getElementById("resolveResult").innerText = err.message;
  }
}

// View escrow info
async function viewEscrow() {
  try {
    await connect();
    const id = document.getElementById("viewEscrowId").value;
    const e = await contract.getEscrow(id);

    // status mapping
    const statusMap = ["AWAITING_FUNDS", "FUNDED", "COMPLETE", "REFUNDED"];

    const obj = {
      buyer: e[0],
      seller: e[1],
      arbiter: e[2],
      amountWei: e[3].toString(),
      amountEth: ethers.utils.formatEther(e[3]),
      status: statusMap[e[4]] || e[4]
    };

    document.getElementById("viewResult").innerText =
      JSON.stringify(obj, null, 2);
  } catch (err) {
    document.getElementById("viewResult").innerText = err.message;
  }
}

// Bind buttons
document.getElementById("createBtn").onclick = createEscrow;
document.getElementById("fundBtn").onclick = fundEscrow;
document.getElementById("resolveBtn").onclick = resolveEscrow;
document.getElementById("viewBtn").onclick = viewEscrow;
