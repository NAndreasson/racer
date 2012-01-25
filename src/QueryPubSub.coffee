transaction = require './transaction.server'

# TODO When an attribute changes, move that doc into a new subscription data set but
# out of an existing subscription data set

# Appraoches:
# 1. Most naive - Run all subscription queries every x seconds
# 2. Every mutation returns a full doc or docs. We pass that doc and the diff
# through a subset of queries to decide (a) which queries to remove this doc
# from and (b) which queries to add this doc to
# 3.Instead of passing a doc and diff, pass just the mutation parameters.
# Figure out which queries to pass it to. When the queries receive the
# mutation, decide which docs to remove (if any) from the query based on the
# mutation. BUT this doesn't handle the case of updating a doc that does not
# belong to any query, but with the update it now belongs to a query. In this
# case, we need to pass the entire doc to the appropriate queries
LiveQuery = require './LiveQuery'
_query_ = require './query'

QueryPubSub = module.exports = (@_channelPubSub) ->
  @_liveQueries = {}
  return

QueryPubSub::=
  subscribe: (subscriberId, queries, callback) ->
    liveQs = @_liveQueries
    channels = []
    for query in queries
      liveQuery = _query_.deserialize query.serialize(), LiveQuery
      queryHash = query.hash()
      liveQs[queryHash] = liveQuery
      channels.push "queries.#{queryHash}"
    @_channelPubSub.subscribe subscriberId, channels, callback, 'subscribe'
    @

  publish: (message, diff) ->
    if txn = message.txn # vs message.ot
      return unless transaction.method(txn) == 'set'

      doc = transaction.args(txn)[1]
      txnPath = transaction.path txn
      [txnNs, txnId] = txnPath.split '.'
      nsPlusId = txnNs + '.' + txnId

      queries = @_liveQueries
      channelPubSub = @_channelPubSub

      for hash, q of queries
        continue unless q.test doc, nsPlusId
        channelPubSub.publish "queries.#{hash}", message
    @

  unsubscribe: (subscriberId, queries, callback) ->
    liveQs = @_liveQueries
    channels = []
    for q in queries
      hash = q.hash()
      delete liveQs[hash]
      channels.push hash
    @_channelPubSub.unsubscribe subscriberId, channels, callback
