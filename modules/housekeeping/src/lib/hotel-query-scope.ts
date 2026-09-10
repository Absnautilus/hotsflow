export function hotelFilter(hotelId: string, column = 'hotel_id'): [column: string, value: string] {
  return [column, hotelId]
}

export function realtimeHotelFilter(hotelId: string): string {
  return `hotel_id=eq.${hotelId}`
}
