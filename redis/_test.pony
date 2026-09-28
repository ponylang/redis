use "buffered"
use "pony_test"

actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  fun tag tests(test: PonyTest) =>
    // Parser property tests
    test.property(_TestRespParserRoundtrip)
    test.property(_TestRespParserValidBytesAlwaysParse)
    test.property(_TestRespParserIncompleteReturnsNone)
    test.property(_TestRespParserInvalidTypeByteErrors)

    // Parser example tests
    test(_TestRespParserEmptyBuffer)
    test(_TestRespParserSimpleString)
    test(_TestRespParserError)
    test(_TestRespParserInteger)
    test(_TestRespParserBulkString)
    test(_TestRespParserArray)
    test(_TestRespParserMultipleValues)
    test(_TestRespParserMalformedErrors)
    test(_TestRespParserIntegerOverflow)
    test(_TestRespParserResp3Null)
    test(_TestRespParserBoolean)
    test(_TestRespParserDouble)
    test(_TestRespParserBigNumber)
    test(_TestRespParserBulkError)
    test(_TestRespParserVerbatimString)
    test(_TestRespParserMap)
    test(_TestRespParserSet)
    test(_TestRespParserPush)

    // Serializer property tests
    test.property(_TestRespSerializerCommandRoundtrip)
    test.property(_TestRespSerializerOutputIsValidResp)

    // Serializer example tests
    test(_TestRespSerializerSimpleCommand)
    test(_TestRespSerializerSingleElement)
    test(_TestRespSerializerEmptyCommand)
    test(_TestRespSerializerBinaryData)

    // Session integration tests
    test(_TestSessionConnectAndReady)
    test(_TestSessionSetAndGet)
    test(_TestSessionConnectionFailure)
    test(_TestSessionExecuteBeforeReady)
    test(_TestSessionExecuteAfterClose)
    test(_TestSessionMultipleCommands)
    test(_TestSessionPipeline)
    test(_TestSessionPipelineMixedResponses)
    test(_TestSessionPipelineClose)
    test(_TestSessionServerError)
    test(_TestSessionPubSub)
    test(_TestSessionPubSubPattern)
    test(_TestSessionExecuteWhileSubscribed)
    test(_TestSessionPubSubBackToReady)
    test(_TestSessionPipelineDrain)
    test(_TestSessionSSLConnectionFailure)
    test(_TestSessionSSLConnectAndReady)
    test(_TestSessionSSLSetAndGet)
    test(_TestSessionResp3ConnectAndReady)
    test(_TestSessionResp3SetAndGet)
    test(_TestSessionResp3FallbackToResp2)

    // Session backpressure test (uses fake server, no Redis needed)
    test(_TestSessionBackpressureOverflow)

    // Command construction unit tests
    test(_TestBuildHelloCommand)
    test(_TestBuildAuthCommand)

    // RespConvert property tests
    test.property(_TestRespConvertAsString)
    test.property(_TestRespConvertAsBytes)
    test.property(_TestRespConvertAsInteger)
    test.property(_TestRespConvertAsBool)
    test.property(_TestRespConvertAsArray)
    test.property(_TestRespConvertAsDouble)
    test.property(_TestRespConvertAsBigNumber)
    test.property(_TestRespConvertAsMap)
    test.property(_TestRespConvertAsSet)
    test.property(_TestRespConvertAsError)
    test.property(_TestRespConvertIsOk)

    // RespConvert example tests
    test(_TestRespConvertIsOkExamples)
    test(_TestRespConvertAsErrorBulkExample)

    // Command builder property tests
    test.property(_TestRedisKeyDelProperty)
    test.property(_TestRedisKeyExistsProperty)
    test.property(_TestRedisStringMgetProperty)
    test.property(_TestRedisListLpushProperty)
    test.property(_TestRedisListRpushProperty)
    test.property(_TestRedisSetSaddProperty)
    test.property(_TestRedisSetSremProperty)
    test.property(_TestRedisHashHdelProperty)
    test.property(_TestRedisStringMsetProperty)

    // Command builder example tests
    test(_TestRedisServerExamples)
    test(_TestRedisStringExamples)
    test(_TestRedisKeyExamples)
    test(_TestRedisHashExamples)
    test(_TestRedisListExamples)
    test(_TestRedisSetExamples)

    // Command API integration test
    test(_TestCommandAPISetAndGet)
