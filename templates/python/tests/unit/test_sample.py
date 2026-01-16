"""Sample unit tests demonstrating pytest usage."""


def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b


def multiply(a: int, b: int) -> int:
    """Multiply two numbers."""
    return a * b


class TestAdd:
    """Test cases for add function."""

    def test_add_positive_numbers(self) -> None:
        """Test adding positive numbers."""
        assert add(2, 3) == 5

    def test_add_negative_numbers(self) -> None:
        """Test adding negative numbers."""
        assert add(-1, -1) == -2

    def test_add_zero(self) -> None:
        """Test adding zero."""
        assert add(5, 0) == 5


class TestMultiply:
    """Test cases for multiply function."""

    def test_multiply_positive_numbers(self) -> None:
        """Test multiplying positive numbers."""
        assert multiply(2, 3) == 6

    def test_multiply_by_zero(self) -> None:
        """Test multiplying by zero."""
        assert multiply(5, 0) == 0

    def test_multiply_negative_numbers(self) -> None:
        """Test multiplying negative numbers."""
        assert multiply(-2, -3) == 6
