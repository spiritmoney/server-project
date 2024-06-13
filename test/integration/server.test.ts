jest.mock("ethers");
jest.mock("readline", () => {
  return {
    createInterface: jest.fn().mockReturnValue({
      question: (prompt: string, cb: (answer: string) => void) =>
        cb("mockPrivateKey"),
      close: jest.fn(),
    }),
  };
});
jest.mock("../src/abi.json", () => ({}), { virtual: true });

const { ethers } = require("ethers");
const readline = require("readline");
const mockAbi = require("../src/abi.json");

// Mock ethers functionality
ethers.Wallet = jest
  .fn()
  .mockImplementation(() => ({ address: "mockAddress" }));
ethers.providers.JsonRpcProvider = jest.fn();
ethers.Contract = jest.fn().mockImplementation(() => ({
  distro: jest.fn().mockResolvedValue({
    wait: jest.fn().mockResolvedValue("mockTransactionReceipt"),
  }),
}));

// Import the module and the function if it's a named export
const serverModule = require("../../src/server");
describe("server.ts functionality", () => {
  let clock: any;

  beforeAll(() => {
    clock = jest.useFakeTimers();
  });

  afterAll(() => {
    clock.runOnlyPendingTimers();
    clock.useRealTimers();
  });

  it("calls performScheduledTask at midnight", async () => {
    // Ensure the function exists and is exported
    expect(serverModule.performScheduledTask).toBeDefined();

    const now = new Date();
    const midnight = new Date(now);
    midnight.setUTCHours(24, 0, 0, 0); // Next midnight UTC
    const msUntilMidnight = midnight.getTime() - now.getTime();

    const performScheduledTaskSpy = jest.spyOn(
      serverModule,
      "performScheduledTask"
    );

    require("../../src/server"); // Assuming the code is in server.ts and exported appropriately

    clock.advanceTimersByTime(msUntilMidnight);

    expect(performScheduledTaskSpy).toHaveBeenCalled();

    // Clean up
    performScheduledTaskSpy.mockRestore();
  });
});
