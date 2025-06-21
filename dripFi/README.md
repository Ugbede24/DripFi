# 💧 DripFi - Micropayment Streaming Smart Contract

**DripFi** is a Clarity smart contract for streaming tokenized micropayments on the Stacks blockchain. It enables programmable, trustless, and time-based fund distribution with advanced features such as stream pausing, resuming, topping up, and cancelling — perfect for subscription models, payroll automation, and continuous payments in decentralized ecosystems.

---

## 🚀 Features

- 🔁 **Continuous Payment Streams** – Stream tokens per second to recipients.
- ⏸️ **Pause & Resume** – Temporarily suspend and restart streams with accurate accounting.
- 🧾 **Finite Streams** – Define streams with optional end times.
- 📈 **Top-up Support** – Add funds to existing streams.
- 🔄 **Withdrawal Mechanism** – Recipients can withdraw earned funds anytime.
- 🧍 **User Tracking** – Tracks sender/receiver balances, stream history, and stream IDs.
- 🔒 **Secure Authorization** – Only stream owners can modify their streams.

---

## 📦 Contract Structure

| Component              | Description                                  |
|------------------------|----------------------------------------------|
| `streams`              | Stores stream metadata and state             |
| `user-balances`        | Stores token balances per user               |
| `user-stream-count`    | Tracks number of streams per user            |
| `user-sent-streams`    | Maps users to sent stream IDs                |
| `user-received-streams`| Maps users to received stream IDs            |
| `stream-counter`       | Global counter for stream ID indexing        |

---

## 🛠️ Functions

### 🔐 Public Functions
- `deposit(amount)` – Add funds to your account
- `withdraw(amount)` – Withdraw from your own balance
- `create-stream(recipient, rate-per-second, deposit, duration)` – Open a new stream
- `withdraw-from-stream(stream-id)` – Withdraw streamed funds as recipient
- `pause-stream(stream-id)` – Pause an active stream (sender only)
- `resume-stream(stream-id)` – Resume a paused stream (sender only)
- `cancel-stream(stream-id)` – Cancel an active stream and refund unearned balance
- `top-up-stream(stream-id, amount)` – Add more funds to a stream

### 📊 Read-Only Functions
- `get-balance(user)` – View user balance
- `get-stream(stream-id)` – View stream details
- `get-available-amount(stream-id)` – View withdrawable amount from a stream
- `get-user-stream-count(user)` – Count of sent/received streams per user
- `get-user-sent-stream(user, index)` – Get a specific sent stream ID
- `get-user-received-stream(user, index)` – Get a specific received stream ID
- `get-total-streams()` – Total number of created streams
- `has-stream-ended(stream-id)` – Check if a stream ended naturally or was terminated

---

## ⚙️ Example Use Cases

- **SaaS Subscriptions**: Stream payments per second for real-time service access.
- **Freelancer Payroll**: Automate milestone-based continuous payments.
- **Content Platforms**: Drip earnings to creators in real time.
- **DeFi Protocols**: Build dynamic liquidity or incentive mechanisms.

---

## 🔐 Security & Best Practices

- Only the **stream creator** can pause, resume, top-up, or cancel a stream.
- Contract enforces **rate-per-second and deposit validations**.
- Tracks **paused durations** and ensures accurate stream accounting on resume.
- All balances are **internally tracked** to prevent overpayment or misuse.

---

## 🧪 Testing & Deployment

To test and deploy DripFi:

1. Use [Clarinet](https://docs.stacks.co/write-smart-contracts/clarinet/overview) for local testing.
2. Deploy to a Stacks testnet or mainnet.
3. Integrate with a front-end to allow users to manage their streams via UI.

---

## 🙌 Contributing

Contributions, issues, and feature requests are welcome! Feel free to fork and improve **DripFi**.
