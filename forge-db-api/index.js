const Fastify = require('fastify')
const { Pool } = require('pg')

const fastify = Fastify({ logger: false })
fastify.register(require('@fastify/formbody'))

const pool = new Pool({
  connectionString: process.env.DATABASE_URL ||
    `postgresql://forge:${process.env.FORGE_DB_PASSWORD}@forge-postgres:5432/forge`
})

fastify.post('/query', async (req, reply) => {
  const sql = req.body?.sql
  if (!sql) return reply.status(400).send({ error: 'sql fehlt' })
  const params = req.body?.params
    ? JSON.parse(req.body.params)
    : []
  try {
    const result = await pool.query(sql, params)
    return { rows: result.rows, rowCount: result.rowCount, command: result.command }
  } catch (err) {
    return reply.status(500).send({ error: err.message })
  }
})

fastify.get('/health', async () => {
  try {
    await pool.query('SELECT 1')
    return { status: 'ok' }
  } catch (err) {
    return { status: 'error', error: err.message }
  }
})

fastify.listen({ port: 3002, host: '0.0.0.0' }, err => {
  if (err) { console.error(err); process.exit(1) }
  console.log('forge-db-api :3002')
})
