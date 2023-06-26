# Generated by the protocol buffer compiler.  DO NOT EDIT!
# Source: test_service.proto for package 'GRPCHelper'

require 'grpc'
require 'test_service_pb'

module GRPCHelper
  module Testing
    class Service

      include ::GRPC::GenericService

      self.marshal_class_method = :encode
      self.unmarshal_class_method = :decode
      self.service_name = 'ruby.test.Testing'

      rpc :Basic, ::GRPCHelper::TestMessage, ::GRPCHelper::TestMessage
      rpc :Error, ::GRPCHelper::TestMessage, ::GRPCHelper::TestMessage
      rpc :StreamFromClient, stream(::GRPCHelper::TestMessage), ::GRPCHelper::TestMessage
      rpc :StreamFromServer, ::GRPCHelper::TestMessage, stream(::GRPCHelper::TestMessage)
      rpc :StreamBothWays, stream(::GRPCHelper::TestMessage), stream(::GRPCHelper::TestMessage)
    end

    Stub = Service.rpc_stub_class
  end
end
