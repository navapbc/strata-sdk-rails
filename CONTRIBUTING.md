# Contributing to Strata SDK

Thank you for your interest in contributing to Strata SDK! We welcome contributions from the community and are excited to work with you to make government digital services more accessible and effective.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Getting Started with Local Development](#getting-started-with-local-development)
- [Making Your First Contribution](#making-your-first-contribution)
- [Pull Request Process](#pull-request-process)
- [Code Review Process](#code-review-process)
- [Development Guidelines](#development-guidelines)
- [Additional Resources](#additional-resources)

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to [strata@navapbc.com](mailto:strata@navapbc.com).

## How Can I Contribute?

There are many ways to contribute to Strata SDK:

- **Report bugs**: If you find a bug, please [open an issue](https://github.com/navapbc/strata-sdk-rails/issues/new?template=bug_report.md) with details about the problem
- **Suggest enhancements**: Have ideas for new features? [Open an issue](https://github.com/navapbc/strata-sdk-rails/issues/new?template=feature_request.md) to discuss it
- **Improve documentation**: Help make our docs clearer and more comprehensive
- **Submit code changes**: Fix bugs, add features, or improve performance

### Good First Issues

New to the project? Look for issues labeled:
- `good first issue` - Perfect for newcomers
- `help wanted` - We'd love your help
- `documentation` - Great for getting familiar with the codebase

## 💻 Getting Started with Local Development

### Prerequisites

Before you begin, ensure you have the following installed:

- **[Docker](https://www.docker.com/)** - Required for running the local database
- **[Node.js](https://nodejs.org)** - JavaScript runtime (LTS version recommended)
- **Ruby 3.4.2** - As specified in [`.ruby-version`](./.ruby-version)
- **Ruby Version Manager** (Required for most users): 
  - [rbenv](https://github.com/rbenv/rbenv) (recommended)

### Initial Setup

1. **Clone the repository** (or your fork):
   ```bash
   git clone https://github.com/navapbc/strata-sdk-rails.git
   cd strata-sdk-rails
   ```

2. **Run the setup command** (this will install dependencies, create the `.env` file, and initialize the database):
   ```bash
   make setup
   ```

   This command will:
   - Install Ruby and Node.js dependencies
   - Create a `.env` file in `./spec/dummy/.env` based on the template at `./spec/dummy/local.env.example`
   - Start the Docker database container
   - Run database migrations and seed data

3. **Verify the setup** by running the test suite:
   ```bash
   make test
   ```

### Development Commands

Here are the most commonly used commands for development:

- **Run tests**: `make test`
- **Run tests in watch mode**: `make test-watch` (automatically re-runs tests on file changes)
- **Run linter**: `make lint` (with auto-fixing)
- **Start dummy app server**: `make start` (for testing the SDK locally)
- **Database commands**:
  - Initialize database: `make init-db`
  - Reset database: `make db-reset`
  - Run migrations: `make db-migrate`
  - Rollback migration: `make db-rollback`
  - Access database console: `make db-console`

For a full list of available commands, run:
```bash
make help
```

## 🔧 Making Your First Contribution

### 1. Fork the Repository

1. Navigate to [https://github.com/navapbc/strata-sdk-rails](https://github.com/navapbc/strata-sdk-rails)
2. Click the "Fork" button in the top right corner
3. This creates a copy of the repository in your GitHub account

### 2. Clone Your Fork

```bash
git clone https://github.com/YOUR-USERNAME/strata-sdk-rails.git
cd strata-sdk-rails
```

### 3. Set Up Upstream Remote

Add the original repository as an upstream remote to keep your fork in sync:

```bash
git remote add upstream https://github.com/navapbc/strata-sdk-rails.git
```

### 4. Create a Branch

Create a new branch for your contribution:

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix-name
```

Branch naming conventions:
- `feature/` for new features
- `fix/` for bug fixes
- `docs/` for documentation updates
- `refactor/` for code refactoring

### 5. Make Your Changes

- Write your code
- Add or update tests as needed
- Update documentation if applicable
- Run tests and linter to ensure everything passes:
  ```bash
  make test
  make lint
  ```

### 6. Commit Your Changes

Write clear, descriptive commit messages:

```bash
git add .
git commit -m "Add feature: brief description of your change"
```

Good commit message examples:
- `Fix: Correct validation error in address form`
- `Add: Support for multi-language form labels`
- `Docs: Update installation instructions for macOS`
- `Refactor: Simplify business process state machine`

### 7. Keep Your Branch Updated

Regularly sync your branch with the upstream main branch:

```bash
git fetch upstream
git rebase upstream/main
```

### 8. Push Your Changes

```bash
git push origin feature/your-feature-name
```

## Pull Request Process

### Opening a Pull Request

1. Go to your fork on GitHub
2. Click "Compare & pull request" button
3. Ensure the base repository is `navapbc/strata-sdk-rails` and base branch is `main`
4. Fill out the PR template with:
   - **Clear title**: Summarize the change in one line
   - **Description**: Explain what changes you made and why
   - **Related issues**: Reference any related issues (e.g., "Fixes #123")
   - **Testing**: Describe how you tested your changes
   - **Screenshots**: Include if applicable (UI changes)

### PR Checklist

Before submitting your PR, ensure:

- [ ] Code follows the project's style guidelines (run `make lint`)
- [ ] All tests pass (run `make test`)
- [ ] New code has appropriate test coverage
- [ ] Documentation has been updated (if applicable)
- [ ] Commit messages are clear and descriptive
- [ ] Branch is up to date with `main`

## Code Review Process

### What to Expect

1. **Initial Review**: A maintainer will review your PR within 3-5 business days
2. **Feedback**: You may receive comments, questions, or requests for changes
3. **Iteration**: Make requested changes and push updates to your branch
4. **Approval**: Once approved by at least one maintainer, your PR will be merged
5. **Merge**: A maintainer will merge your PR into the main branch

### Review Criteria

Reviewers will evaluate:

- **Code quality**: Is the code clean, maintainable, and well-structured?
- **Tests**: Are there adequate tests? Do they cover edge cases?
- **Documentation**: Are changes documented appropriately?
- **Performance**: Does the change introduce any performance concerns?
- **Accessibility**: For UI changes, are accessibility standards met?
- **Security**: Are there any security implications?

### Responding to Feedback

- Be open to constructive criticism
- Ask questions if feedback is unclear
- Make requested changes in new commits (don't force push during review)
- Mark conversations as resolved once addressed
- Be patient and respectful

Thank you for contributing to Strata SDK! Your efforts help make government digital services better for everyone. 
