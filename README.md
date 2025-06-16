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

A `Success` result contains the `value` returned by the interactor, while a `Failure` result contains an `error` value. Both result types respond to `#success?` and `#failure?` methods to check their status. They also provide a `#meta` method to access metadata about the execution, such as the class name, properties.

A failure will return immediately.

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

### Metadata Tracking

Every interactor automatically tracks metadata including class information and property values:

```ruby
result = CreateUser.call(email: "test@example.com", name: "Test User")

assert result.meta == {
  class: CreateUser,
  props: { email: "test@example.com", name: "Test User", age: 18 }
}
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

### Running Tests and Linting

```bash
# Run all tests
bundle exec rspec

# Run linting
bundle exec rubocop

# Run both tests and linting
bundle exec rake
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/budu/mu-action.

When contributing:

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`bundle exec rspec`)
5. Ensure code follows style guidelines (`bundle exec rubocop`)
6. Commit your changes (`git commit -am 'Add some feature'`)
7. Push to the branch (`git push origin my-new-feature`)
8. Create a new Pull Request

This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/budu/mu-action/blob/main/CODE_OF_CONDUCT.md).

## Acknowledgments

This project stands on the shoulders of giants:

- **[Interactor](https://github.com/collectiveidea/interactor)** by Steve Richert and contributors: The original inspiration for this gem.
- **[Literal](https://literal.fun)** by Joel Drapper and contributors: The type system that makes this gem possible.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Mu::Action project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/budu/mu-action/blob/main/CODE_OF_CONDUCT.md).
