"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const body_parser_1 = __importDefault(require("body-parser"));
const ethers_1 = require("ethers");
const abi = require("../src/abi.json");
const app = (0, express_1.default)();
const port = 5000; // Port number for the Express server
app.use(body_parser_1.default.json()); // Middleware to parse JSON bodies
const contractAddress = "0xDd21Cf61DD3e47cEC1bC5190915D726c8B0876C1";
const url = "https://sepolia.mode.network";
async function performScheduledTask(privateKey) {
    const wallet = new ethers_1.ethers.Wallet(privateKey);
    console.log(`Wallet address: ${wallet.address}`);
    console.log("Performing scheduled task...");
    const provider = new ethers_1.ethers.providers.JsonRpcProvider(url);
    const contract = new ethers_1.ethers.Contract(contractAddress, abi, provider);
    const signer = new ethers_1.ethers.Wallet(privateKey, provider);
    const txSigner = contract.connect(signer);
    const tx = await txSigner.distro();
    await tx.wait();
    console.log("Transaction sent!");
}
app.get("/", (req, res) => {
    res.send("Server running");
});
// POST endpoint to trigger the scheduled task
app.post("/performScheduledTask", async (req, res) => {
    const { privateKey } = req.body;
    if (!privateKey) {
        return res.status(400).send("PrivateKey is required");
    }
    try {
        await performScheduledTask(privateKey);
        res.send("Scheduled task performed successfully");
    }
    catch (error) {
        console.error(error);
        res.status(500).send("Error performing scheduled task");
    }
});
function scheduleTask() {
    const now = new Date();
    const midnightUtc = new Date(now);
    midnightUtc.setUTCHours(24, 0, 0, 0); // Set to next midnight UTC
    const msUntilMidnightUtc = midnightUtc.getTime() - now.getTime();
    setTimeout(() => {
        console.log("Sending POST request to /performScheduledTask at midnight UTC");
        const wallet = ethers_1.ethers.Wallet.createRandom(); //Implement logic for getting privateKey securely
        const privateKey = wallet.privateKey;
        // Replace `http://localhost:5000` with your server's actual URL if different
        fetch("http://localhost:5000/performScheduledTask", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ privateKey }), // Replace with actual method to securely retrieve the privateKey
        })
            .then((response) => response.text())
            .then((result) => console.log(result))
            .catch((error) => console.error("Error:", error));
        // Schedule the next call
        scheduleTask();
    }, msUntilMidnightUtc);
}
app.listen(port, () => {
    console.log(`Server running on port ${port}`);
});
//# sourceMappingURL=server.js.map