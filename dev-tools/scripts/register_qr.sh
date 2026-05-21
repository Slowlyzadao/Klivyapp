#!/bin/bash
curl -s -X POST http://localhost:3002/register \
  -H "Content-Type: application/json" \
  -d '{"phone_number":"QR_1771670092004"}'
echo ""
