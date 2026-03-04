import { useEffect, useState } from 'react'
import './App.css'

const API_URL = import.meta.env.VITE_API_URL

export default function App() {
  const [rows, setRows] = useState(null)
  const [error, setError] = useState(null)

  useEffect(() => {
    fetch(API_URL)
      .then(res => {
        if (!res.ok) throw new Error('Unable to load data (Status: ' + res.status + ')')
        return res.json()
      })
      .then(data => setRows(data))
      .catch(err => {
        const msg = err.message === 'Failed to fetch' ? 'Network error' : err.message
        setError(msg)
        console.error('Fetch Error:', err)
      })
  }, [])

  const renderBody = () => {
    if (error) {
      return (
        <tr>
          <td colSpan={4} className="error">{error}</td>
        </tr>
      )
    }
    if (rows === null) {
      return (
        <tr>
          <td colSpan={4} className="loading">Loading...</td>
        </tr>
      )
    }
    if (rows.length === 0) {
      return (
        <tr>
          <td colSpan={4} className="loading">No data yet.</td>
        </tr>
      )
    }
    return rows.map(row => {
      const pct = parseFloat(row.pct_change || 0)
      const price = parseFloat(row.close_price || 0)
      const sign = pct >= 0 ? '+' : ''
      const cls = pct >= 0 ? 'gain' : 'loss'
      return (
        <tr key={row.date + row.ticker_symbol}>
          <td className="ticker">{row.ticker_symbol || '---'}</td>
          <td>{row.date || '---'}</td>
          <td>{'$' + price.toFixed(2)}</td>
          <td><span className={'badge ' + cls}>{sign + pct.toFixed(2) + '%'}</span></td>
        </tr>
      )
    })
  }

  return (
    <>
      <h1>Top Movers</h1>
      <p className="subtitle">Biggest daily % mover from stock watchlist — last 7 trading days</p>
      <table>
        <thead>
          <tr>
            <th>Ticker</th>
            <th>Date</th>
            <th>Close</th>
            <th>Change</th>
          </tr>
        </thead>
        <tbody>
          {renderBody()}
        </tbody>
      </table>
    </>
  )
}
