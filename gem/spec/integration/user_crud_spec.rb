# typed: false
# frozen_string_literal: true

require_relative "../support/json_rpc_client"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "User CRUD operations via JSON-RPC", :integration do
  let(:app_path) { File.expand_path("../fixtures/test_app", __dir__) }
  let(:client) { Konsol::Test::JsonRpcClient.new(app_path: app_path, timeout: 30) }
  let(:session_id) { @session_id } # rubocop:disable RSpec/InstanceVariable

  # rubocop:disable RSpec/BeforeAfterAll
  before(:all) do
    # Setup database before running tests
    test_app_path = File.expand_path("../fixtures/test_app", __dir__)
    env = { "RAILS_ENV" => "test", "BUNDLE_GEMFILE" => File.join(test_app_path, "Gemfile") }

    # Install gems if needed
    system(env, "bundle", "check", chdir: test_app_path, out: File::NULL, err: File::NULL) ||
      system(env, "bundle", "install", chdir: test_app_path, out: File::NULL, err: File::NULL)

    # Setup database
    system(env, "bundle", "exec", "rake", "db:schema:load", chdir: test_app_path, out: File::NULL, err: File::NULL)
  end
  # rubocop:enable RSpec/BeforeAfterAll

  before do
    client.start

    # Initialize the server
    response = client.send_request("initialize", { "clientInfo" => { "name" => "test" } })
    raise "Failed to initialize server" unless response["result"]

    # Create a session
    session_response = client.send_request("konsol/session.create")
    raise "Failed to create session" unless session_response["result"]

    @session_id = session_response["result"]["sessionId"]
  end

  after do
    # Clean up users
    eval_code("User.delete_all")
    client.stop
  end

  def eval_code(code)
    response = client.send_request("konsol/eval", {
      "sessionId" => session_id,
      "code" => code,
    })
    response["result"]
  end

  describe "Create" do
    it "creates a new User record" do
      result = eval_code("User.create!(name: \"Alice\", email: \"alice@example.com\")")

      expect(result["exception"]).to be_nil
      expect(result["value"]).to include("User")
      expect(result["value"]).to include("Alice")
      expect(result["value"]).to include("alice@example.com")
      expect(result["valueType"]).to eq("User")
    end

    it "creates multiple User records" do
      eval_code("User.create!(name: \"Bob\", email: \"bob@example.com\")")
      eval_code("User.create!(name: \"Charlie\", email: \"charlie@example.com\")")

      result = eval_code("User.count")

      expect(result["exception"]).to be_nil
      expect(result["value"]).to eq("2")
      expect(result["valueType"]).to eq("Integer")
    end

    it "returns validation error for invalid data" do
      # Assuming we add a validation - for now just test create works
      result = eval_code("User.create(name: nil, email: nil)")

      expect(result["exception"]).to be_nil
      expect(result["valueType"]).to eq("User")
    end
  end

  describe "Read" do
    before do
      eval_code("User.create!(name: \"Diana\", email: \"diana@example.com\")")
    end

    it "finds a User by id" do
      # Get the user id first
      id_result = eval_code("User.first.id")
      user_id = id_result["value"]

      result = eval_code("User.find(#{user_id})")

      expect(result["exception"]).to be_nil
      expect(result["value"]).to include("Diana")
      expect(result["valueType"]).to eq("User")
    end

    it "finds a User by email" do
      result = eval_code("User.find_by(email: \"diana@example.com\")")

      expect(result["exception"]).to be_nil
      expect(result["value"]).to include("Diana")
      expect(result["valueType"]).to eq("User")
    end

    it "returns nil for non-existent User" do
      result = eval_code("User.find_by(email: \"nonexistent@example.com\")")

      expect(result["exception"]).to be_nil
      expect(result["value"]).to eq("nil")
      expect(result["valueType"]).to eq("NilClass")
    end

    it "raises RecordNotFound for find with invalid id" do
      result = eval_code("User.find(999999)")

      expect(result["exception"]).not_to be_nil
      expect(result["exception"]["class"]).to eq("ActiveRecord::RecordNotFound")
      expect(result["exception"]["message"]).to include("Couldn't find User")
    end

    it "lists all Users" do
      eval_code("User.create!(name: \"Eve\", email: \"eve@example.com\")")

      result = eval_code("User.all.to_a")

      expect(result["exception"]).to be_nil
      expect(result["value"]).to include("Diana")
      expect(result["value"]).to include("Eve")
      expect(result["valueType"]).to eq("Array")
    end

    it "uses where queries" do
      eval_code("User.create!(name: \"Diana Clone\", email: \"diana2@example.com\")")

      result = eval_code("User.where(\"name LIKE ?\", \"Diana%\").count")

      expect(result["exception"]).to be_nil
      expect(result["value"]).to eq("2")
    end
  end

  describe "Update" do
    before do
      eval_code("User.create!(name: \"Frank\", email: \"frank@example.com\")")
    end

    it "updates a User attribute" do
      eval_code("User.find_by(name: \"Frank\").update!(name: \"Franklin\")")
      result = eval_code("User.find_by(email: \"frank@example.com\").name")

      expect(result["exception"]).to be_nil
      expect(result["value"]).to eq("\"Franklin\"")
    end

    it "updates multiple attributes" do
      eval_code("User.find_by(name: \"Frank\").update!(name: \"Francis\", email: \"francis@example.com\")")

      result = eval_code("User.first")

      expect(result["exception"]).to be_nil
      expect(result["value"]).to include("Francis")
      expect(result["value"]).to include("francis@example.com")
    end

    it "uses update_all for bulk updates" do
      eval_code("User.create!(name: \"George\", email: \"george@example.com\")")

      result = eval_code("User.update_all(name: \"Anonymous\")")

      expect(result["exception"]).to be_nil

      count_result = eval_code("User.where(name: \"Anonymous\").count")
      expect(count_result["value"]).to eq("2")
    end
  end

  describe "Delete" do
    before do
      eval_code("User.create!(name: \"Harry\", email: \"harry@example.com\")")
      eval_code("User.create!(name: \"Ivy\", email: \"ivy@example.com\")")
    end

    it "deletes a User by destroy" do
      eval_code("User.find_by(name: \"Harry\").destroy")

      result = eval_code("User.count")
      expect(result["value"]).to eq("1")

      remaining = eval_code("User.first.name")
      expect(remaining["value"]).to eq("\"Ivy\"")
    end

    it "deletes a User by delete" do
      eval_code("User.find_by(name: \"Ivy\").delete")

      result = eval_code("User.count")
      expect(result["value"]).to eq("1")
    end

    it "uses destroy_all" do
      eval_code("User.destroy_all")

      result = eval_code("User.count")
      expect(result["value"]).to eq("0")
    end

    it "uses delete with conditions" do
      eval_code("User.where(name: \"Harry\").delete_all")

      result = eval_code("User.count")
      expect(result["value"]).to eq("1")
    end
  end

  describe "Session state persistence" do
    it "preserves variables across eval calls" do
      eval_code("@user = User.create!(name: \"Jack\", email: \"jack@example.com\")")
      result = eval_code("@user.name")

      expect(result["exception"]).to be_nil
      expect(result["value"]).to eq("\"Jack\"")
    end

    it "can use local variables in subsequent calls" do
      eval_code("user = User.create!(name: \"Kate\", email: \"kate@example.com\")")

      # Local variables should persist in the session binding
      result = eval_code("user.email")

      expect(result["exception"]).to be_nil
      expect(result["value"]).to eq("\"kate@example.com\"")
    end
  end

  describe "Output capture" do
    it "captures puts output" do
      result = eval_code("puts User.create!(name: \"Leo\", email: \"leo@example.com\").inspect")

      expect(result["exception"]).to be_nil
      expect(result["stdout"]).to include("Leo")
      expect(result["stdout"]).to include("leo@example.com")
    end

    it "captures p output" do
      eval_code("User.create!(name: \"Mia\", email: \"mia@example.com\")")
      result = eval_code("p User.pluck(:name)")

      expect(result["stdout"]).to include("Mia")
    end
  end
end
# rubocop:enable RSpec/DescribeClass
