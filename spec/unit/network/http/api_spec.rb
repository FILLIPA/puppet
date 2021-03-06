#! /usr/bin/env ruby

require 'spec_helper'
require 'puppet_spec/handler'
require 'puppet/network/http'

describe Puppet::Network::HTTP::API do
  def respond(text)
    lambda { |req, res| res.respond_with(200, "text/plain", text) }
  end

  describe "#not_found" do
    let(:response) { Puppet::Network::HTTP::MemoryResponse.new }

    let(:routes) {
      Puppet::Network::HTTP::Route.path(Regexp.new("foo")).
      any.
      chain(Puppet::Network::HTTP::Route.path(%r{^/bar$}).get(respond("bar")),
            Puppet::Network::HTTP::API.not_found)
    }

    it "mounts the chained routes" do
      request = Puppet::Network::HTTP::Request.from_hash(:path => "foo/bar")
      routes.process(request, response)

      expect(response.code).to eq(200)
      expect(response.body).to eq("bar")
    end

    it "responds to unknown paths with a 404" do
      request = Puppet::Network::HTTP::Request.from_hash(:path => "foo/unknown")

      expect do
        routes.process(request, response)
      end.to raise_error(Puppet::Network::HTTP::Error::HTTPNotFoundError)
    end
  end

  describe "Puppet API" do
    let(:handler) { PuppetSpec::Handler.new(Puppet::Network::HTTP::API.master_routes,
                                            Puppet::Network::HTTP::API.ca_routes) }

    let(:master_prefix) { Puppet::Network::HTTP::MASTER_URL_PREFIX }
    let(:ca_prefix) { Puppet::Network::HTTP::CA_URL_PREFIX }

    it "raises a not-found error for non-CA or master routes" do
      req = Puppet::Network::HTTP::Request.from_hash(:path => "/unknown")
      res = {}
      handler.process(req, res)
      expect(res[:status]).to eq(404)
    end

    describe "when processing master routes" do
      it "responds to v3 indirector requests" do
        req = Puppet::Network::HTTP::Request.from_hash(:path => "#{master_prefix}/v3/node/foo",
                                                       :params => {:environment => "production"},
                                                       :headers => {'accept' => "pson"})
        res = {}
        handler.process(req, res)
        expect(res[:status]).to eq(200)
      end

      it "responds to v3 environments requests" do
        req = Puppet::Network::HTTP::Request.from_hash(:path => "#{master_prefix}/v3/environments")
        res = {}
        handler.process(req, res)
        expect(res[:status]).to eq(200)
      end

      it "responds to v2.0 environments requests" do
        req = Puppet::Network::HTTP::Request.from_hash(:path => "#{master_prefix}/v2.0/environments")
        res = {}
        handler.process(req, res)
        expect(res[:status]).to eq(200)
      end

      it "responds with a not found error to non-v3/2.0 requests" do
        req = Puppet::Network::HTTP::Request.from_hash(:path => "#{master_prefix}/unknown")
        res = {}
        handler.process(req, res)
        expect(res[:status]).to eq(404)
      end
    end

    describe "when processing CA routes" do
      it "responds to v1 indirector requests" do
        Puppet::SSL::Certificate.indirection.stubs(:find).returns "foo"
        req = Puppet::Network::HTTP::Request.from_hash(:path => "#{ca_prefix}/v1/certificate/foo",
                                                       :params => {:environment => "production"},
                                                       :headers => {'accept' => "s"})
        res = {}
        handler.process(req, res)
        expect(res[:body]).to eq("foo")
        expect(res[:status]).to eq(200)
      end

      it "responds with a not found error to non-v1 requests" do
        req = Puppet::Network::HTTP::Request.from_hash(:path => "#{ca_prefix}/unknown")
        res = {}
        handler.process(req, res)
        expect(res[:status]).to eq(404)
      end
    end
  end
end
