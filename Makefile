# Install dependencies
install:
	pip install -r requirements.txt

# Lint the code
lint:
	pylint src/

# Clean up temporary files
clean:
	rm -rf __pycache__ .pytest_cache .pylint.d
