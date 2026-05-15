// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ALLOWANCE");
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(balanceOf[from] >= amount, "BALANCE");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract MockWETH is MockERC20 {
    bool public shortWithdraw;

    constructor() MockERC20("Wrapped Ether", "WETH", 18) {}

    receive() external payable {}

    function deposit() external payable {
        totalSupply += msg.value;
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "BALANCE");
        uint256 delivered = shortWithdraw ? amount - 1 : amount;
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
        payable(msg.sender).transfer(delivered);
    }

    function setShortWithdraw(bool shortWithdraw_) external {
        shortWithdraw = shortWithdraw_;
    }
}

contract TransferTaxERC20 is MockERC20 {
    uint256 public immutable taxBps;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 taxBps_)
        MockERC20(name_, symbol_, decimals_)
    {
        taxBps = taxBps_;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(balanceOf[from] >= amount, "BALANCE");
        uint256 tax = (amount * taxBps) / 10_000;
        uint256 delivered = amount - tax;
        balanceOf[from] -= amount;
        balanceOf[to] += delivered;
        totalSupply -= tax;
        emit Transfer(from, to, delivered);
        if (tax != 0) emit Transfer(from, address(0), tax);
    }
}

contract RevertingBalanceToken {
    function balanceOf(address) external pure returns (uint256) {
        revert("BALANCE_REVERT");
    }
}

contract ShortBalanceToken {
    fallback() external {
        if (msg.sig == 0x70a08231) {
            assembly {
                mstore(0x00, 0x1234)
                return(0x1e, 0x02)
            }
        }
    }
}
