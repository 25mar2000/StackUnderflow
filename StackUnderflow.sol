// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
//import "imports/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "hardhat/console.sol";
import "github.com/provable-things/ethereum-api/provableAPI.sol";
//import "imports/SafeMath.sol";

// Child of the ERC20 standard implementation that checks if the sender is the owner
// specified upon creation of the contract when creating or destroying tokens
contract RewardTokens is ERC20("Reward Token", "VT") {
    address _owner;

    constructor(address owner){
        _owner = owner;
    }

    modifier onlyOwner {
        // ERC20 recomends using _msgSender instead of directly using msg.sender
        // (see ./imports/utils/Context.sol)
        require(_msgSender() == _owner, "You must be the owner of the RewardTokens!");
        _;
    }

    function create(address account, uint256 amount) external onlyOwner {
        super._mint(account, amount);
    }

    function destroy(address account, uint256 amount) external onlyOwner {
        super._burn(account, amount);
    }
}

contract ContractRepository {
    address _owner;             // Owner of contract
    RewardTokens _vt;           // Contract managing tokens
    uint public _tokenPrice;    // Price of each token
    uint public _maxTokens;     // Maximum number of tokens that can be created


    // Current participants
    mapping(address => bool) _participants;
    uint _numParticipants;


    // Struct representing contracts and its mapping
    struct Post {
        string title;
        string description;

        address _ipfsHash; //Descripción del contrato y de las vulnerabilidades/problemas a descubrir
        address _contract; //Contrato a revisar
        uint tokens;       // Número de tokens para las soluciones
        uint comunityReward; //Número e tokens para la comunidad que testee las soluciones propuestas

        uint[] answers;
        uint chosen;
        //address[] participants; // Array to later iterate over all participants of a proposal
        address creator; //Persona que pide la revisión de un contrato
    }

    struct Answer {
        address _contract; //Contrato a revisar
        uint _post;

        address _ipfsHash; //Descripción de la solución al problema
        address _atacante; //Contrato desde el que se ha realizado el ataque/ problemas a solventar

        uint posVotes; //Votos positivos a esta solucion
        uint negVotes; //Votos negativos a esta solucion
        address[] firstPos;  //Primeras personas que han votado de forma positiva a una respuesta

        address creator; //Persona que responde al post

    }

    mapping(uint => Post) _proposalsMapping; 
    mapping(uint => Answer) _answerPost;
    mapping(address => mapping(uint => bool) ) _votesPeoplePosts;

    uint[] _unansweredPosts;
    uint[] _answeredPosts;
    uint[] _closedPosts;

    uint _id_counter;
    uint _answer_counter;

    // Mapping from a participant to the prposals and the proposal to the number of votes total
    mapping(address => mapping(uint => uint)) _participantToProposalVotes;

    constructor(uint tokenPrice, uint maxTokens){
        _owner = msg.sender;
        _tokenPrice = tokenPrice;
        _maxTokens = maxTokens;
        _vt = new RewardTokens(address(this));

        _numParticipants = 0;
        _id_counter = 1000;
        _answer_counter = 1000;
    }

    modifier onlyOwner {
        require(msg.sender == _owner, "You must be the owner of ContractRepository!");
        _;
    }


    modifier onlyParticipants {
        require(_participants[msg.sender], "You are not a participant!");
        _;
    }

    modifier onlyPostPublisher(uint post) {
        require(msg.sender == _proposalsMapping[post].creator , "You must be the creator of the Post to perform this action!");
        _;
    }

    // Funcción para crear y asignar todos los tokens que se quieran comprar 
    function _buyTokens(uint value, address sender, uint cuantity) private {
        // Check that at least 1 token can be bought
        require(value >= (_tokenPrice*cuantity), string(abi.encodePacked("You must buy at least 1 token (", Strings.toString(_tokenPrice), " wei)")));

        // Check that number of tokens that can be bought + the total amount of created tokens doesn't exceed the maximum number of tokens
        require((cuantity + _vt.totalSupply()) <= _maxTokens, string(abi.encodePacked("Amount of tokens exceeds maximum supply (", Strings.toString(_maxTokens - _vt.totalSupply()), " tokens left)")));
        
        // Create and assign all the tokens that can be bought with the amount sent
        _vt.create(sender, cuantity);

        // Give back the remainder
        uint remainder = value - (_tokenPrice*cuantity);
        payable(sender).transfer(remainder);
    }


    function enterRepository(uint numTokens) public payable {
        // Check that user is not already a participant
        require(_participants[msg.sender] != true, "You are already a participant in this repository!");

        // Buy tokens
        _buyTokens(msg.value, msg.sender, numTokens);

        // Register participant
        _participants[msg.sender] = true;
        _numParticipants++;
    }

    function addContract(string calldata title, string calldata description, address ipfsHash, address _contract, uint rewardTokens, uint comunityTokens) public onlyParticipants returns (uint){
        
        //Comprobar que el emisor tiene la sufciente cantidad de tokens para añadir el contrato
        //Cantidad de token del sender
        uint n_tokens = _vt.balanceOf(msg.sender);

        //Creo que tiene que hacerse payabñe
        //require(msg.sender == provable_cbAddress());
        //emit LogNewProvableQuery("Provable query was sent, standing by for the answer...");
        //hay que ver juntos la API porque no me aclaro donde sale el owner
        //provable_query("URL", "xml(https://api-goerli.etherscan.io/api?module=contract&action=getabi&address=%22+_contract+%22&apikey=A4YGKSZC84BFGWCZI5E3HEI76FTGCX52PK).inputs%22); 
        //con la request de arriba recogeriamos el owner y lo comparamos a msg.sender para comprobar si es el real

        // Check if participant has enough tokens
        require(n_tokens >= rewardTokens, "No tienes suficientes tokens para poner ese reward");

        // Destruimos los tokens
        _vt.destroy(msg.sender, rewardTokens);

        //Generate a new post with the given data and tokens
        Post memory proposal = Post(title, description, ipfsHash ,_contract , rewardTokens, comunityTokens, new uint[](0), 0, msg.sender);

        //Set the id of the newly created proposal
        uint id = _id_counter;
        _id_counter++;

        // Add proposal to mapping and array of ids
        _proposalsMapping[id] = proposal;


        return id;
    }

    function addSolutionToPost(uint postNum, address ipfsHashSolution, address solutionContract) public onlyParticipants{

        Post memory _post =  _proposalsMapping[postNum];
        Answer memory _answer = Answer(_post._contract,postNum, ipfsHashSolution, solutionContract, 0, 0, new address[](0), msg.sender);
        _answer_counter++;
        _answerPost[_answer_counter] = _answer;
        _proposalsMapping[postNum].answers.push(_answer_counter);

    }

    //Elegimos una solución
    function closePost(uint postId, uint solution) public onlyParticipants  onlyPostPublisher(postId){
        Post memory _post =  _proposalsMapping[postId];
        Answer memory _answer = _answerPost[solution];
        require(_post.chosen == 0, "Post is already closed");
        require(_answer._contract != address(0), string(abi.encodePacked("Answer asocited with id (", Strings.toString(solution), " does not exist")));
        require(_answer._contract == _post._contract, "Answer does not belong to the contract");
        

        _post.chosen = solution;
        uint tokens = _post.tokens;
        uint comunity = _post.comunityReward;

        //Creamos los tokens para el creador del contrato
        _vt.create(_answer.creator, tokens);

        uint len = _answer.firstPos.length;
        address [] memory winners= _answer.firstPos;
        for(uint i = 0; i < len; i++){
            _vt.create(winners[i], 1);
        }

        if(len < comunity){
            _vt.create(msg.sender, comunity - len);
        }

    }

    //Las votaciones positivas sirven para que el usuario sepa cuanta gente ha tratado una respuesta
    //
    function votePosAnswerId(uint idAnswer) public onlyParticipants{

        //Sacamos la solución
        Answer memory _answer = _answerPost[idAnswer];
        Post memory _post = _proposalsMapping[_answer._post];
        uint postId = _answer._post;
        
        require(_votesPeoplePosts[msg.sender][idAnswer] == false, string(abi.encodePacked("You have already voted an answer to this question: ", Strings.toString(solution), " does not exist")));
        
        uint posV = ++_answerPost[idAnswer].posVotes;
        
        if(posV < _post.comunityReward){
            _answerPost[idAnswer].firstPos.push(msg.sender);
        } 
        //Asignamos que una persona ha votado positivamente a una solucion       
        _votesPeoplePosts[msg.sender][idAnswer] = true;

    }

    //Las votaciones negativas solo sirven para que en usuario sepa cuanta gente a intentado hacer una respuesta
    function voteNegAnswerId(uint idAnswer) public onlyParticipants{

        //Answer memory _answer = _answerPost[idAnswer];
        _answerPost[idAnswer].negVotes++;        

    }


    //Compramos tokens
    function buyTokens(uint amount) public payable onlyParticipants {
        _buyTokens(msg.value, msg.sender, amount);
    }

    //Devuelve el dinero de los tokens
    function sellTokens(uint amount) onlyParticipants public {
        //Cantidad de token del sender
        uint n_tokens = _vt.balanceOf(msg.sender);

        // Check if participant has enough tokens
        require(n_tokens >= amount, "You don't have enough tokens");

        // Destroy tokens
        _vt.destroy(msg.sender, amount);

        // Send corresponding value
        uint value = amount * _tokenPrice;
        payable(msg.sender).transfer(value);
    }

    //View functions

    function getERC20() public view returns (address){
        return address(_vt);
    }


    function getPostInfo(uint postId) public view onlyParticipants returns (string memory, string memory, address, address, uint, address) {
        Post memory _post = _proposalsMapping[postId];

        // Check que el ID se corresponde con un Post
        require(bytes(_post.title).length > 0, "There is no proposal corresponding to the provided ID!");
        
        return (_post.title, _post.description, _post._ipfsHash, _post._contract, _post.tokens, _post.creator);
    }

    function getUnansweredPostsIds() public view returns (uint[] memory){
        return _unansweredPosts;
    }

    function getAnsweredPostsIds() public view returns (uint[] memory){
        return _answeredPosts;
    }

    function getClosedPostsIds() public view returns (uint[] memory){
        return _closedPosts;
    }

    function getUnansweredPosts() public view returns (Post[] memory){
        uint len = _answeredPosts.length;
        Post[] memory UnansweredPosts = new Post[](len);
        for(uint i = 0; i < len; i++){
            uint pos = _unansweredPosts[i];
            UnansweredPosts[i] = _proposalsMapping[pos];
        }
        return UnansweredPosts;
    }

    function getAnsweredPosts() public view returns (Post[] memory){
        uint len = _answeredPosts.length;
        Post[] memory AnsweredPosts = new Post[](len);
        for(uint i = 0; i < len; i++){
            uint pos = _answeredPosts[i];
            AnsweredPosts[i] = _proposalsMapping[pos];
        }
        return AnsweredPosts;
    }

    function getClosedPosts() public view returns (Post[] memory){
        uint len = _closedPosts.length;
        Post[] memory ClosedPosts = new Post[](len);
        for(uint i = 0; i < len; i++){
            uint pos = _closedPosts[i];
            ClosedPosts[i] = _proposalsMapping[pos];
        }
        return ClosedPosts;
    }



}