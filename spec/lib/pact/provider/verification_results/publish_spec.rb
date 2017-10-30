require 'pact/provider/verification_results/publish'

module Pact
  module Provider
    module VerificationResults
      describe Publish do
        describe "call" do
          let(:publish_verification_url) { nil }
          let(:tag_version_url) { 'http://tag-me/{tag}' }
          let(:pact_source) { instance_double("Pact::Provider::PactSource", pact_hash: pact_hash, uri: pact_url)}
          let(:pact_url) { instance_double("Pact::Provider::PactURI", basic_auth?: basic_auth, username: 'username', password: 'password')}
          let(:basic_auth) { false }
          let(:pact_hash) do
            {
              'consumer' => {
                'name' => 'Foo'
              },
              '_links' => {
                'pb:publish-verification-results'=> {
                  'href' => publish_verification_url
                },
                'pb:tag-version'=> {'href' => tag_version_url}
              }
            }
          end
          let(:app_version_set) { false }
          let(:verification_json) { '{"foo": "bar"}' }
          let(:publish_verification_results) { false }
          let(:tags) { [] }
          let(:verification) do
            instance_double("Pact::Verifications::Verification",
              to_json: verification_json,
              provider_application_version_set?: app_version_set
            )
          end

          let(:provider_configuration) do
            double('provider config', publish_verification_results?: publish_verification_results, tags: tags)
          end

          before do
            allow($stdout).to receive(:puts)
            allow(Pact.configuration).to receive(:provider).and_return(provider_configuration)
            stub_request(:post, 'http://broker/verifications')
            stub_request(:put, /tag-me/)
          end

          subject { Publish.call(pact_source, verification)}

          context "when publish_verification_results is false" do
            it "does not publish the verification" do
              subject
              expect(WebMock).to_not have_requested(:post, 'http://broker/verifications')
            end
          end

          context "when publish_verification_results is true" do
            let(:publish_verification_results) { true }

            context "when the publish-verification link is present" do
              let(:publish_verification_url) { 'http://broker/verifications' }

              it "publishes the verification" do
                subject
                expect(WebMock).to have_requested(:post, publish_verification_url).with(body: verification_json, headers: {'Content-Type' => 'application/json'})
              end

              context "with tags" do
                let(:tags) { ['foo'] }

                it "tags the provider version" do
                  subject
                  expect(WebMock).to have_requested(:put, 'http://tag-me/foo').with(headers: {'Content-Type' => 'application/json'})
                end

                context "when there is no pb:tag-version link" do
                  before do
                    pact_hash['_links'].delete('pb:tag-version')
                  end

                  it "prints a warning" do
                    expect($stderr).to receive(:puts).with /WARN: Cannot tag provider version/
                    subject
                  end
                end
              end

              context "when basic auth is configured on the pact URL" do
                let(:basic_auth) { true }
                it "sets the username and password for the pubication URL" do
                  subject
                  expect(WebMock).to have_requested(:post, publish_verification_url).with(basic_auth: ['username', 'password'])
                end
              end

              context "when an HTTP error is returned" do
                it "raises a PublicationError" do
                  stub_request(:post, 'http://broker/verifications').to_return(status: 500, body: 'some error')
                  expect{ subject }.to raise_error(PublicationError, /Error returned/)
                end
              end

              context "when the connection can't be made" do
                it "raises a PublicationError error" do
                  allow(Net::HTTP).to receive(:start).and_raise(SocketError)
                  expect{ subject }.to raise_error(PublicationError, /Failed to publish verification/)
                end
              end

              context "with https" do
                before do
                  stub_request(:post, publish_verification_url)
                end
                let(:publish_verification_url) { 'https://broker/verifications' }

                it "uses ssl" do
                  subject
                  expect(WebMock).to have_requested(:post, publish_verification_url)
                end
              end
            end
          end
        end
      end
    end
  end
end
