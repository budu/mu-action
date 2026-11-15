# Mu::Action

`Mu::Action` is a Ruby gem that provides a modern interactor pattern implementation with enhanced type safety, metadata tracking, and a hook system. Built on top of the excellent [Literal](https://literal.fun) gem, it offers a structured approach to encapsulating business logic in single-purpose, composable objects.

This project is heavily inspired by the [Interactor](https://github.com/collectiveidea/interactor) gem.

## What is an Interactor?

An interactor is a design pattern that encapsulates a single piece of business logic. Instead of cramming complex operations into controllers or models, interactors provide a clean, testable way to organize your application's core functionality.

Think of interactors as specialized service objects that:

- Have a single responsibility
- Receive input parameters
- Return structured results (success or failure)
- Can be easily tested in isolation
- Compose well with other interactors

Basically, it's like a component for your business logic.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'mu-action'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install mu-action
```

## Usage

### Basic Interactor

Create an interactor by including `Mu::Action` and implementing a `call` method:

```ruby
class CreateUser
  include Mu::Action

  prop :email, String
  prop :name, String
  prop :age, Integer, default: 18

  def call
    Failure(:user_exists) if User.exists?(email: @email)
    user = User.create!(email: @email, name: @name, age: @age)
    Success(user)
  end
end
```

### Results

A `Success` result contains the `value` returned by the interactor, while a `Failure` result contains an `error` value, usually a symbol, and a `details` hash built from the keyword arguments given to `Failure`. Both result types respond to `#success?` and `#failure?` methods to check their status. They also provide a `#meta` method to access metadata about the execution, such as the class name and properties. Metadata is for diagnostics; anything a caller needs belongs in `details`. An interactor with nothing to return can call `Success()` without a value.

A failure will return immediately.

Inside an action class, the constants of `Mu::Action` come before top-level constants with the same name: `Result`, `Success`, `Failure`, `FailureError`, `Context`, `Metadata`, `Hooks`, `Failures`, `ClassMethods`, `VERSION` and `CONTEXT_KEY`. If your application has its own `Result` or `Context` class, for example, write `::Result` or `::Context` inside an action.

### Calling Interactors

Interactors can be called in two ways:

```ruby
# Returns a Result object (Success or Failure)
result = CreateUser.call(email: "jane@example.com", name: "Jane")

case result
in Mu::Action::Success(value:)
  puts "Created user: #{value.name}"
in Mu::Action::Failure(error:)
  puts "Failed: #{error}"
end

# Returns the value on success, raises an exception on failure
user = CreateUser.call!(email: "jane@example.com", name: "Jane")
assert user.name == "Jane"
assert user.email == "jane@example.com"
```

### Hooks

Add cross-cutting concerns with before, after, and around hooks:

```ruby
class ProcessPayment
  include Mu::Action

  prop :amount, Float
  prop :card_token, String

  before do
    meta[:started_at] = Time.now
    Rails.logger.info "Processing payment for $#{@amount}"
  end

  after do
    meta[:completed_at] = Time.now
    Rails.logger.info "Payment processing completed"
  end

  around do |action, chain|
    ActiveRecord::Base.transaction do
      chain.call
    end
  end

  def call
    # Payment processing logic here
    Success(payment_id: "pay_123")
  end
end

result = ProcessPayment.call(amount: 100.0, card_token: "tok_123")
assert result.value[:payment_id] == "pay_123"
```

Hooks can also be registered by method name if you prefer keeping the logic in dedicated instance methods:

```ruby
class ProcessPayment
  include Mu::Action

  prop :amount, Float
  prop :card_token, String

  before :prepare_logging
  after :finalize_logging
  around :wrap_in_transaction

  def prepare_logging
    meta[:started_at] = Time.now
    Rails.logger.info "Processing payment for $#{@amount}"
  end

  def finalize_logging
    meta[:completed_at] = Time.now
    Rails.logger.info "Payment processing completed"
  end

  def wrap_in_transaction(chain)
    ActiveRecord::Base.transaction { chain.call }
  end

  def call
    Success(payment_id: "pay_123")
  end
end
```

Around hook methods may also receive no arguments and use `yield`, or accept two arguments `(action, chain)` to mirror the block-based signature.

### Custom Result Types

Define typed results for better API contracts:

```ruby
class RollaDice
  include Mu::Action

  result _Integer(1..6)

  def call
    Success rand 1..6
  end
end

result = RollaDice.call!
assert (1..6).cover? result
```

The result method above is just a shortcut for the type of the value property of the Success class.

```ruby
class RollaDice
  include Mu::Action

  class Success < Mu::Action::Success
    prop :value, _Integer(1..6), :positional
  end

  def call
    Success rand 1..6
  end
end

result = RollaDice.call!
assert (1..6).cover? result
```

You can refer to the [Literal documentation](https://literal.fun/docs) for more details on the [built-in types](https://literal.fun/docs/built-in-types.html) or see some [example types](https://literal.fun/docs/example-types.html).

### Failures

`Failure` takes an error code and, optionally, details as keyword arguments:

```ruby
class RenameProject
  include Mu::Action

  prop :name, String

  def call
    Failure(:invalid, errors: ["name can't be blank"]) if @name.empty?
    Success(@name)
  end
end

case RenameProject.call(name: "")
in Mu::Action::Failure(error: :invalid, details: { errors: })
  assert errors == ["name can't be blank"]
end
```

An interactor can declare the failures it returns, with the types of their details. Once it declares any, an undeclared failure or a detail of the wrong type raises an `ArgumentError`. Interactors without declarations accept any failure.

```ruby
class PublishArticle
  include Mu::Action

  failure :already_published
  failure :invalid, errors: _Array(String)

  prop :title, String

  def call
    Failure(:invalid, errors: ["title is missing"]) if @title.empty?
    Success(@title)
  end
end

assert PublishArticle.failures.keys == %i[already_published invalid]
```

To report undeclared failures instead of raising, give `Mu::Action.on_undeclared_failure` a callable. It receives the interactor, the error code and the details, and the failure goes through:

```ruby
Mu::Action.on_undeclared_failure = lambda do |action, error, details|
  Rails.logger.info "#{action.class} returned undeclared failure #{error.inspect}"
end

Mu::Action.on_undeclared_failure = :raise # the default
```

To compose interactors, call the inner one with `call!`. Its failure becomes the outer interactor's failure, with the same error and details, and the inner `Failure` is kept in `meta[:cause]`. Use `failure from:` to accept every failure of the inner interactor:

```ruby
class PublishFeaturedArticle
  include Mu::Action

  failure from: PublishArticle

  prop :title, String

  def call
    title = PublishArticle.call!(title: @title)
    Success("Featured: #{title}")
  end
end

result = PublishFeaturedArticle.call(title: "")
assert result.error == :invalid
assert result.meta[:cause].meta[:class] == PublishArticle
```

Because the inner failure is raised as an exception, around hooks such as transactions see it and can roll back.

### Metadata Tracking

Every interactor automatically tracks metadata including class information and property values:

```ruby
result = CreateUser.call(email: "test@example.com", name: "Test User")

assert result.meta == {
  class: CreateUser,
  props: { email: "test@example.com", name: "Test User", age: 18 }
}
```

To keep sensitive or bulky props out of the metadata, choose which ones are recorded:

```ruby
class SignIn
  include Mu::Action

  record_props except: %i[password]   # or only: [...], or record_props false

  prop :email, String
  prop :password, String

  def call = Success(@email)
end

assert SignIn.call(email: "jane@example.com", password: "secret").meta[:props] == { email: "jane@example.com" }
```

### Context

Information about who is calling and from where, such as the actor, the account or the channel, goes in `context` rather than in props. It's available in hooks and in `call`, and it's recorded in `meta[:context]`. It can be any object.

```ruby
class ArchiveProject
  include Mu::Action

  prop :project_id, Integer

  before do
    meta[:archived_by] = context[:actor]
  end

  def call = Success(@project_id)
end

result = ArchiveProject.call(project_id: 42, context: { actor: "jane", channel: :web })
assert result.meta[:archived_by] == "jane"
```

Interactors called by another one inherit its context, so a hook in a nested interactor sees the same actor. Pass `context:` explicitly to override it.

The context follows the call stack: an interactor inherits it when it is called directly by an interactor that is running. A thread or a fiber started by an interactor does not inherit it, so hand it over explicitly:

```ruby
class WhoIsActing
  include Mu::Action

  def call = Success(context && context[:actor])
end

class ActInBackground
  include Mu::Action

  def call
    inherited = Thread.new { WhoIsActing.call! }.value
    handed_over = Thread.new { WhoIsActing.call!(context:) }.value
    Success([inherited, handed_over])
  end
end

assert ActInBackground.call!(context: { actor: "jane" }) == [nil, "jane"]
```

`context` and `meta` are reserved prop names: declaring a prop with one of them raises an `ArgumentError`. The context is set before the other props, so a prop default can read it:

```ruby
class Greet
  include Mu::Action

  prop :locale, Symbol, default: -> { context ? context[:locale] : :en }

  def call = Success(@locale == :fr ? "Bonjour" : "Hello")
end

assert Greet.call!(context: { locale: :fr }) == "Bonjour"
assert Greet.call! == "Hello"
```

## Differences from the Interactor Gem

The main difference and the motivation for creating `Mu::Action` is to separate the context into inputs, an output, and metadata. This allows for a more structured approach to handling business logic, making it easier to reason about the flow of data and the state of the application.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run the tests with:

```bash
bundle exec rspec
```

You can also run `bin/console` for an interactive prompt to experiment with the gem.

To install this gem onto your local machine, run `bundle exec rake install`.

### Running the Checks

`bin/ci` runs RuboCop, RSpec, Steep and the README examples. It runs them on every supported Ruby version, switching between them with [asdf](https://asdf-vm.com), and installs missing gems from the lockfile.

```bash
# Run every check on each supported Ruby version
bin/ci

# Run every check on some Ruby versions only
bin/ci 3.2 4.0

# Run every check on the current Ruby only (no asdf needed)
bin/ci --current

# Run the tests or the linter alone
bundle exec rspec
bundle exec rubocop
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/budu/mu-action.

When contributing:

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Write tests for your changes
4. Ensure all checks pass (`bin/ci`)
5. Commit your changes (`git commit -am 'Add some feature'`)
6. Push to the branch (`git push origin my-new-feature`)
7. Create a new Pull Request

This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/budu/mu-action/blob/main/CODE_OF_CONDUCT.md).

## Acknowledgments

This project stands on the shoulders of giants:

- **[Interactor](https://github.com/collectiveidea/interactor)** by Steve Richert and contributors: The original inspiration for this gem.
- **[Literal](https://literal.fun)** by Joel Drapper and contributors: The type system that makes this gem possible.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Mu::Action project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/budu/mu-action/blob/main/CODE_OF_CONDUCT.md).
