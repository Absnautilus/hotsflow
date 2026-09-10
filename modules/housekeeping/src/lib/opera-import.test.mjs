import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { parseOperaArrivals, operaDateToLocalValue } from './opera-import.ts'

// Synthetic fixture reproducing the real report's quirks with invented
// names/rooms only -- never a real Opera export.
const SAMPLE = [
  '101\tRossi,Mario\t\t2609GROUP\t09/09/26\t10/09/26\tJSGV\t1\t0\t1\tCASH\tWEBNR\t\t00:00\t00:00\tDue In\t',
  '220\tVerdi,Anna\t\t2609GROUP\t09/09/26\t10/09/26\tCLA\t1\t0\t1\tCASH\tWEBNR\t006\tBianchi,Luca\tS- Agency\t\t09/09/26\t11/09/26\tJSUICV\t2\t1\t1\tDATATRS\tWEBRONR\t\t14:34\t00:00\tDue In\t',
  '105\tFerrari,Giulia\t\t2609GROUP\t09/09/26\t13/09/26\tSUP\t2\t0\t1\tCASH\tWEBFREE\t\t00:00\t00:00\tDue In\t56\t2\t35\t2\t',
  '\tTBA,TBA\tT- OC TRAVEL\t2608OCSPEC\t09/09/26\t11/09/26\tCLA\t1\t0\t1\tCASH\tWEBNR\t\t00:00\t00:00\tDue In\t56\t2\t35\t2\t',
].join('\n')

describe('parseOperaArrivals', () => {
  it('parses a simple single-booking line, keeping first and last name', () => {
    const { rows } = parseOperaArrivals(SAMPLE)
    const row = rows.find((r) => r.roomNumber === '101')
    assert.deepEqual(row, { roomNumber: '101', guestName: 'Mario Rossi', arrivalDate: '09/09/26', departureDate: '10/09/26' })
  })

  it('splits a line that concatenates two bookings back to back', () => {
    const { rows } = parseOperaArrivals(SAMPLE)
    const first = rows.find((r) => r.roomNumber === '220')
    const second = rows.find((r) => r.roomNumber === '006')
    assert.equal(first?.guestName, 'Anna Verdi')
    assert.equal(second?.guestName, 'Luca Bianchi')
    assert.equal(second?.departureDate, '11/09/26')
  })

  it('ignores trailing page-total numbers appended after the status field', () => {
    const { rows } = parseOperaArrivals(SAMPLE)
    const row = rows.find((r) => r.roomNumber === '105')
    assert.deepEqual(row, { roomNumber: '105', guestName: 'Giulia Ferrari', arrivalDate: '09/09/26', departureDate: '13/09/26' })
  })

  it('keeps a booking with no room assigned yet (TBA) with roomNumber null', () => {
    const { rows } = parseOperaArrivals(SAMPLE)
    const row = rows.find((r) => r.roomNumber === null)
    assert.equal(row?.guestName, 'TBA TBA')
  })

  it('falls back to the surname alone when no first name follows the comma', () => {
    const { rows } = parseOperaArrivals('101\tSolo\t\t2609GROUP\t09/09/26\t10/09/26\tJSGV\t1\t0\t1\tCASH\tWEBNR\t\t00:00\t00:00\tDue In\t')
    assert.equal(rows[0]?.guestName, 'Solo')
  })

  it('extracts every booking, including both from the concatenated line', () => {
    const { rows } = parseOperaArrivals(SAMPLE)
    assert.equal(rows.length, 5)
  })

  it('reports a warning for a line with no recognizable date pair', () => {
    const { warnings } = parseOperaArrivals('this is not a report line\n101\tRossi,Mario\t\t2609GROUP\t09/09/26\t10/09/26\tJSGV\t1\t0\t1\tCASH\tWEBNR\t\t00:00\t00:00\tDue In\t')
    assert.equal(warnings.length, 1)
  })
})

describe('operaDateToLocalValue', () => {
  it('converts a DD/MM/YY date plus a time of day to a local datetime-picker value', () => {
    assert.equal(operaDateToLocalValue('09/09/26', '15:00'), '2026-09-09T15:00')
  })

  it('zero-pads single-digit day and month', () => {
    assert.equal(operaDateToLocalValue('5/3/26', '11:00'), '2026-03-05T11:00')
  })
})
