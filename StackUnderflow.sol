// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

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

    function buyTokens(uint value, uint cuantity, uint _tokenPrice, uint _maxTokens, address sender) external onlyOwner{
        // Comprobamos que el valor mandado es mayor que el precio total a pagar
        require(value >= (_tokenPrice*cuantity), string(abi.encodePacked("Not enought funds to buy ", Strings.toString(cuantity), " tokens")));

        // Check that number of tokens that can be bought + the total amount of created tokens doesn't exceed the maximum number of tokens
        require((cuantity + super.totalSupply()) <= _maxTokens, string(abi.encodePacked("Amount of tokens exceeds maximum supply (", Strings.toString(_maxTokens - super.totalSupply()), " tokens left)")));
        
        // Create and assign all the tokens that can be bought with the amount sent
        create(sender, cuantity);
    }

    function sellTokens(address sender, uint amount) external onlyOwner{
        //Cantidad de token del sender
        uint n_tokens = super.balanceOf(sender);

        // Check if participant has enough tokens
        require(n_tokens >= amount, string(abi.encodePacked("You don't have enough tokens (amount: ", Strings.toString(n_tokens))));

        // Destroy tokens
        destroy(sender, amount);
    }

    function create(address account, uint256 amount) public onlyOwner {
        super._mint(account, amount);
    }

    function destroy(address account, uint256 amount) public onlyOwner {
        super._burn(account, amount);
    }

    //Funciones para bloquear los tokens y desbloquearlos manteniedo el total de tokens
    function lockTokens(uint amount, address sender) external onlyOwner{
        super._transfer(sender, _owner, amount);
    }

    function transferTo(uint amount, address to) external onlyOwner{
        super._transfer(_owner, to, amount);
    }
}

//Auxiliary contract to divide the functinality
contract Utils{

    function findPost(uint[] memory init, uint changeId) public pure returns (uint){
        uint i = 0;
        uint len = init.length;
        bool found = false;
        while((i < len) && !found){
            if(init[i] == changeId){
                found= true;
            }else{
                i++;
            }
        }
        return i;
    }

}


contract ContractRepository {
    address _owner;             // Owner of contract
    RewardTokens _vt;           // Contract managing tokens
    uint public _tokenPrice;    // Price of each token
    uint public _maxTokens;     // Maximum number of tokens that can be created

    Utils _utils;

    // Current participants
    mapping(address => bool) _participants;
    uint public _numParticipants;


    // Struct representing contracts and its mapping
    struct Post {
        string title;
        string description;

        string _ipfsLink; //Descripción del contrato y de las vulnerabilidades/problemas a descubrir
        address _contract; //Contrato a revisar
        uint tokens;       // Número de tokens para las soluciones
        uint comunityReward; //Número e tokens para la comunidad que testee las soluciones propuestas

        uint[] answers;
        uint chosen;
        address creator; //Persona que pide la revisión de un contrato
    }

    struct Answer {
        uint _post;

        string _ipfsLink; //Descripción de la solución al problema
        address _solution; //Contrato desde el que se ha realizado el ataque/ problemas a solventar

        uint posVotes; //Votos positivos a esta solucion
        address[] firstPos;  //Primeras personas que han votado de forma positiva a una respuesta

        address _creator; //Persona que responde al post

    }

    mapping(uint => Post) _postMapping; 
    mapping(uint => Answer) _answerPost;
    mapping(address => mapping(uint => bool) ) _votesPeoplePosts;

    uint[] _unansweredPosts;
    uint[] _answeredPosts;
    uint[] _closedPosts;

    uint _id_counter;
    uint _answer_counter;

    bool _sem;

    constructor(uint tokenPrice, uint maxTokens){
        _owner = msg.sender;
        _tokenPrice = tokenPrice;
        _maxTokens = maxTokens;
        _vt = new RewardTokens(address(this));
        _utils = new Utils();

        _numParticipants = 0;
        _id_counter = 1000;
        _answer_counter = 1000;
        _sem = false;
    }

    modifier onlyParticipants {
        require(_participants[msg.sender], "You are not a participant!");
        _;
    }

    modifier onlyPostPublisher(uint post) {
        require(msg.sender == _postMapping[post].creator , "You must be the creator of the Post to perform this action!");
        _;
    }

    modifier notClosed(uint postId){
        require(_postMapping[postId].chosen == 0, string(abi.encodePacked( "Post with Id: ", Strings.toString(postId) ," is already closed")));
        _;
    }

    // Funcción para crear y asignar todos los tokens que se quieran comprar 
    function _buyTokens(uint value, address sender, uint cuantity) private {

        _vt.buyTokens(value, cuantity,  _tokenPrice, _maxTokens, sender);
        // Devolvemos el dinero que sobre
        if(value > (_tokenPrice*cuantity)){
            uint remainder = value - (_tokenPrice*cuantity);
            payable(sender).transfer(remainder);
        }
    }

    //Para entrar en el ecosistema
    function enterRepository(uint numTokens) public payable {
        // Check that user is not already a participant
        require(_participants[msg.sender] != true, "You are already a participant in this repository!");

        // Buy tokens
        _buyTokens(msg.value, msg.sender, numTokens);

        // Register participant
        _numParticipants++;
        _participants[msg.sender] = true;
    }

    function addContract(string calldata title, string calldata description, string calldata ipfsHash, address _contract, uint rewardTokens, uint comunityTokens) public onlyParticipants returns (uint){
        
        //Comprobar que el emisor tiene la sufciente cantidad de tokens para añadir el contrato
        //Cantidad de token del sender
        uint n_tokens = _vt.balanceOf(msg.sender);

        //Si se ha añadido un contrato debe implementar Ownable y mandarse desde el mismo address que se pide
        if(_contract != address(0)){
            require(Ownable(_contract).owner() == msg.sender, "The address from which the contract has been added is not the same as the address for the deployment");
        }
        require(bytes(title).length > 0, "Title of Post can't be empty");

        // Check if participant has enough tokens
        uint totalTokens = (rewardTokens+comunityTokens);
        require(n_tokens >= totalTokens, string(abi.encodePacked("No tienes suficentes tokens, tienes: ", Strings.toString(n_tokens), ", has puesto: ", Strings.toString(rewardTokens+comunityTokens))));

        // Destruimos los tokens
        _vt.lockTokens(totalTokens, msg.sender);

        //Generate a new post with the given data and tokens
        Post memory proposal = Post(title, description, ipfsHash ,_contract , rewardTokens, comunityTokens, new uint[](0), 0, msg.sender);

        //Set the id of the newly created proposal
        uint id = _id_counter;
        _id_counter++;

        // Añadimos el post al mapping y al array de post sin responder
        _postMapping[id] = proposal;
        _unansweredPosts.push(id);
        
        //Devolvemos el id del post para que el particiapente sepa cual es su Post
        return id;
    }

    //Añadimos una solución al Post
    function addSolutionToPost(uint postId, string calldata ipfsHashSolution, address solutionContract) public onlyParticipants notClosed(postId) returns (uint){

        //Si se ha añadido un contrato debe implementar Ownable y mandarse desde el mismo address que se pide
        if(solutionContract != address(0)){
            require(Ownable(solutionContract).owner() == msg.sender, "The address from which the contract has been added is not the same as the address for the deployment");
        }

        //Sacamos el post del id
        Post memory _post =  _postMapping[postId];
        require(_post.creator != msg.sender, "You can't answer your own Post");

        Answer memory _answer = Answer(postId, ipfsHashSolution, solutionContract, 0, new address[](0), msg.sender);
        
        //Si el post no tenía respuestas lo cambiamos de una lista a otra
        if(_post.answers.length == 0){
            _changePostState(_unansweredPosts, postId, _answeredPosts);
        }
        //Añado la solucion al mapping
        uint AnsId = _answer_counter;
        _answerPost[AnsId] = _answer;
        //Sumo el contador
        _answer_counter++;
        //Añado el id a la lista de soluciones del post
        _postMapping[postId].answers.push(AnsId);

        return AnsId;

    }

    //Elegimos una solución
    function closePost(uint postId, uint solutionId) public onlyPostPublisher(postId) notClosed(postId){
        Post memory _post =  _postMapping[postId];
        Answer memory _answer = _answerPost[solutionId];
 
        //Comprobamos que la respuesta existe y está asociada al post
        require(_answer._post != 0, string(abi.encodePacked("Answer asocited with id (", Strings.toString(solutionId), " does not exist")));
        require(_answer._post == postId, "Answer does not belong to the contract");
        
        //Asignamos el id de la solución elegida
        _postMapping[postId].chosen = solutionId;

        uint tokens = _post.tokens;
        uint comunity = _post.comunityReward;

        //Creamos los tokens para el creador del contrato
        _vt.transferTo(tokens, _answer._creator);

        uint len = _answer.firstPos.length;
        address [] memory winners= _answer.firstPos;
        for(uint i = 0; i < len; i++){
            _vt.create(winners[i], 1);
        }

        //Si sobran tokens se los devolvemos al que ha hecho el post
        if(len < comunity){
            _vt.create(msg.sender, comunity - len);
        }

        //Cambiamos el estado del post de respondido a cerrado
        _changePostState(_answeredPosts, postId, _closedPosts);

    }

    //Función auxiliar para cambiar el estado de una post
    function _changePostState(uint[] storage init, uint changeId, uint [] storage fin) private {
        
        //Blockeamos las listas para evitar problemas de concurrencia
        while(_sem){}
        _sem = true;

        uint len = init.length;
        uint i = _utils.findPost(init, changeId);
        //Intercambiar por la ultima posición de la lista
        init[i] = init[len-1];
        //Eliminamos la última posicion
        init.pop();

        //Lo añadimos a la lista final
        fin.push(changeId);

        _sem = false;

    }

    //Las votaciones positivas sirven para que el usuario sepa cuanta gente ha tratado una respuesta
    //
    function votePosAnswerId(uint idAnswer) public onlyParticipants{

        //Sacamos la solución
        Answer memory _answer = _answerPost[idAnswer];
        uint postId = _answer._post;
        Post memory _post = _postMapping[postId];
        
        
        //Testeamos que el post está abierto
        require(_postMapping[postId].chosen == 0, string(abi.encodePacked( "Post with Id: ", Strings.toString(postId) ," is already closed")));
        //Testeamos que la persona no haya votado ya aun a solución
        require(_votesPeoplePosts[msg.sender][postId] == false, string(abi.encodePacked("You have already voted an answer to this question: ", Strings.toString(idAnswer))));
        
        require(_answer._creator != msg.sender, "You cannot vote your own answer");
        
        //Sumamos su voto positivo
        uint posV = ++_answerPost[idAnswer].posVotes;
        
        if(posV <= _post.comunityReward){
            _answerPost[idAnswer].firstPos.push(msg.sender);
        } 
        //Asignamos que una persona ha votado positivamente a una solucion de un post      
        _votesPeoplePosts[msg.sender][postId] = true;

    }

    //Compramos tokens
    function buyTokens(uint amount) public payable onlyParticipants {
        _buyTokens(msg.value, msg.sender, amount);
    }

    //Devuelve el dinero de los tokens
    function sellTokens(uint amount) onlyParticipants public payable {

        _vt.sellTokens(msg.sender, amount);
        
        // Send corresponding value
        uint value = amount * _tokenPrice;
        payable(msg.sender).transfer(value);
    }

    //View functions

    //dado un post Id te devuelve los datos de un Post
    function getPostInfo(uint postId) public view onlyParticipants returns (string memory, string memory, string memory, address, uint, uint, uint[] memory, uint, address) {
        Post memory _post = _postMapping[postId];

        // Check que el ID se corresponde con un Post
        require(bytes(_post.title).length > 0, "There is no Post corresponding to the provided ID!");
        
        return (_post.title, _post.description, _post._ipfsLink, _post._contract, _post.tokens, _post.comunityReward, _post.answers, _post.chosen, _post.creator);
    }
    function getTokenAmount()public view returns (uint){
        return _vt.balanceOf(msg.sender);
    }

    //Array de ids de los posts no respondidos aún
    /*function getUnansweredPostsIds() public view returns (uint[] memory){
        return _unansweredPosts;
    }

    //Array de ids de los posts ya respondidos
    function getAnsweredPostsIds() public view returns (uint[] memory){
        return _answeredPosts;
    }

    //Array de ids de los posts cerrados
    function getClosedPostsIds() public view returns (uint[] memory){
        return _closedPosts;
    }*/

    //Array de Posts sin responder 
    function getUnansweredPosts() public view returns (uint[] memory, Post[] memory){
        return (_unansweredPosts, _getPost(_unansweredPosts));
    }

    //Array de Posts con respuestas
    function getAnsweredPosts() public view returns (uint[] memory, Post[] memory){
        return (_answeredPosts, _getPost(_answeredPosts));
    }

    //Array de Posts cerrados
    function getClosedPosts() public view returns (uint[] memory, Post[] memory){
        return (_closedPosts, _getPost(_closedPosts));
    }

    function _getPost(uint[] memory postIds) private view returns (Post[] memory){
        uint len = postIds.length;
        Post[] memory _posts = new Post[](len);
        for(uint i = 0; i < len; i++){
            uint pos = postIds[i];
            _posts[i] = _postMapping[pos];
        }
        return _posts;
    }

    //Get answer from ID
    function getAnswerFromId(uint answerId) public view returns(uint _post, string memory _ipfsLink, address _solution, uint postVotes, address _creator){
        Answer memory _answer = _answerPost[answerId];

        require(_answer._post != 0, string(abi.encodePacked("Answer asocited with id (", Strings.toString(answerId), " does not exist")));
        
        return (_answer._post, _answer._ipfsLink, _answer._solution, _answer.posVotes, _answer._creator);

    }

    function getAnswersFromPost(uint postId) public view returns(uint[] memory, Answer[] memory, bool){
        Post memory _post = _postMapping[postId];
        require(bytes(_post.title).length > 0, "There is no Post corresponding to the provided ID!");

        uint[] memory answers = _post.answers;
        uint len = answers.length;
        require(len > 0 , "Post does not have answers!");

        Answer[] memory lAnswers = new Answer[](len);
        for(uint i = 0; i < len; i++){
            uint idAnswer = answers[i];
            lAnswers[i] = _answerPost[idAnswer];
        }
        bool open = false;
        if(_post.chosen == 0){
            open = true;
        }

        return (answers, lAnswers, open);

    }



}