import { useEffect, useState } from "react";
import "./index.css";

const API = "http://localhost:8080";

function App() {
  const [health, setHealth] = useState(false);
  const [payments, setPayments] = useState([]);
  const [form, setForm] = useState({
    amount: "10000",
    currency: "INR",
    paymentMethod: "card",
  });
  const [message, setMessage] = useState("");

  const checkHealth = async () => {
    try {
      const response = await fetch(`${API}/v1/health`);
      setHealth(response.ok);
    } catch {
      setHealth(false);
    }
  };

  const createPayment = async () => {
    setMessage("");

    try {
      const response = await fetch(`${API}/v1/payments`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": `dashboard-${Date.now()}`,
        },
        body: JSON.stringify({
          amount: Number(form.amount),
          currency: form.currency,
          paymentMethod: form.paymentMethod,
        }),
      });

      const data = await response.json();

      if (!response.ok) {
        setMessage(data.error || "Payment failed");
        return;
      }

      setPayments((current) => [data, ...current]);
      setMessage(`Payment created successfully: ${data.paymentId}`);
    } catch {
      setMessage("Could not connect to PaySwitch API");
    }
  };

  useEffect(() => {
    checkHealth();
  }, []);

  const successful = payments.filter(
    (payment) => payment.status === "Success"
  ).length;

  const failed = payments.filter(
    (payment) => payment.status === "Failed"
  ).length;

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-icon">P</div>
          <div>
            <h1>PaySwitch</h1>
            <span>Payment Orchestration</span>
          </div>
        </div>

        <nav>
          <div className="nav-item active">Dashboard</div>
          <div className="nav-item">Payments</div>
          <div className="nav-item">Routing</div>
          <div className="nav-item">Gateways</div>
          <div className="nav-item">Webhooks</div>
          <div className="nav-item">Reconciliation</div>
        </nav>

        <div className="sidebar-bottom">
          <div className="system-label">SYSTEM</div>
          <div className="health-row">
            <span className={health ? "dot healthy" : "dot"}></span>
            {health ? "API Operational" : "API Offline"}
          </div>
        </div>
      </aside>

      <main className="main">
        <header className="topbar">
          <div>
            <h2>Operations Dashboard</h2>
            <p>Monitor payments, routing and gateway health.</p>
          </div>

          <div className="status">
            <span className={health ? "dot healthy" : "dot"}></span>
            {health ? "System Healthy" : "System Offline"}
          </div>
        </header>

        <section className="stats">
          <div className="stat-card">
            <span>Total Payments</span>
            <strong>{payments.length}</strong>
            <small>Dashboard activity</small>
          </div>

          <div className="stat-card">
            <span>Successful</span>
            <strong>{successful}</strong>
            <small>Successful payments</small>
          </div>

          <div className="stat-card">
            <span>Failed</span>
            <strong>{failed}</strong>
            <small>Failed payments</small>
          </div>

          <div className="stat-card">
            <span>Gateways</span>
            <strong>3</strong>
            <small>Available routes</small>
          </div>
        </section>

        <section className="grid">
          <div className="panel create-panel">
            <div className="panel-header">
              <div>
                <h3>Create Payment</h3>
                <p>Send a payment request to PaySwitch.</p>
              </div>
            </div>

            <label>Amount</label>
            <input
              type="number"
              value={form.amount}
              onChange={(e) =>
                setForm({ ...form, amount: e.target.value })
              }
            />

            <label>Currency</label>
            <select
              value={form.currency}
              onChange={(e) =>
                setForm({ ...form, currency: e.target.value })
              }
            >
              <option value="INR">INR</option>
              <option value="USD">USD</option>
            </select>

            <label>Payment Method</label>
            <select
              value={form.paymentMethod}
              onChange={(e) =>
                setForm({ ...form, paymentMethod: e.target.value })
              }
            >
              <option value="card">Card</option>
            </select>

            <button onClick={createPayment}>Create Payment</button>

            {message && <div className="message">{message}</div>}
          </div>

          <div className="panel">
            <div className="panel-header">
              <div>
                <h3>Gateway Health</h3>
                <p>Current routing candidates.</p>
              </div>
            </div>

            <div className="gateway">
              <div>
                <strong>Stripe</strong>
                <span>Primary gateway</span>
              </div>
              <div className="gateway-status">
                <span className="dot healthy"></span>
                Healthy
              </div>
            </div>

            <div className="gateway">
              <div>
                <strong>MockGateway-B</strong>
                <span>Fallback gateway</span>
              </div>
              <div className="gateway-status">
                <span className="dot healthy"></span>
                Healthy
              </div>
            </div>

            <div className="gateway">
              <div>
                <strong>MockGateway-A</strong>
                <span>Fallback gateway</span>
              </div>
              <div className="gateway-status">
                <span className="dot healthy"></span>
                Healthy
              </div>
            </div>
          </div>
        </section>

        <section className="panel payments-panel">
          <div className="panel-header">
            <div>
              <h3>Recent Payments</h3>
              <p>Payments created from this dashboard.</p>
            </div>
          </div>

          {payments.length === 0 ? (
            <div className="empty">
              No dashboard payments yet. Create your first payment above.
            </div>
          ) : (
            <div className="table-wrapper">
              <table>
                <thead>
                  <tr>
                    <th>Payment ID</th>
                    <th>Amount</th>
                    <th>Currency</th>
                    <th>Method</th>
                    <th>Status</th>
                  </tr>
                </thead>

                <tbody>
                  {payments.map((payment) => (
                    <tr key={payment.paymentId}>
                      <td className="payment-id">{payment.paymentId}</td>
                      <td>{payment.amount}</td>
                      <td>{payment.currency}</td>
                      <td>{payment.paymentMethod}</td>
                      <td>
                        <span
                          className={
                            payment.status === "Success"
                              ? "badge success"
                              : "badge failed"
                          }
                        >
                          {payment.status}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <footer>
          PaySwitch • Haskell Payment Orchestration Engine
        </footer>
      </main>
    </div>
  );
}

export default App;