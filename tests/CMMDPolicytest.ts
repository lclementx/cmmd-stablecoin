import { expect } from 'chai'
import { useCallback, useEffect, useState } from 'react';
import { ethers } from "ethers";

var cmmdAbi_json = require('./cmmdABI.json');
var oracleAbi_json = require('./oracleABI.json');
var policyAbi_json = require('./cmmdPolicyABI.json');
import Web3 from 'web3';
const web3 = new Web3(Web3.givenProvider);


async function exec() {
  const hexToDecimal = hex => parseInt(hex, 16);

   const provider = new ethers.providers.JsonRpcProvider(
    "https://rpc.debugchain.net"
  );
   const wallet = new ethers.Wallet("7c3925dde086856b256b1ed95110f0fb0396bde63e67e8ef37c804b98dea389a", provider);  //private key of metamask wallet
   const signer = wallet.provider.getSigner(wallet.address);

    // fetch abi
    const oracleAbi = JSON.parse(JSON.stringify(oracleAbi_json));
    
    // create contract instance
    const cpiOracleAddress = "0xb31fFa2e5d501F9f606Ff4A5F3E5E281394f7C60";
    const cpiOracle = new ethers.Contract(cpiOracleAddress, oracleAbi, signer);
    const marketOracleAddress = "0x91Be6B000dD141dEC7B71165049D93f50f0253DF";
    const marketOracle = new ethers.Contract(marketOracleAddress, oracleAbi, signer);


    const market = await marketOracle.getData().then(result => result[0]._hex) //First result is the value
    const cpi = await cpiOracle.getData().then(result => result[0]._hex) //First result is the value

    
    console.log("current market price: " + hexToDecimal(market));
    console.log("current cpi: " + hexToDecimal(cpi));

    const policyAbi = JSON.parse(JSON.stringify(policyAbi_json));
    const policyAddress = "0xBc9e50fD908317ccbF9C4050a160D667F41729E5";
    const policyContract = new ethers.Contract(policyAddress, policyAbi, signer);

    policyContract.setCpiOracle(cpiOracle)
    policyContract.setMarketOracle(marketOracle)

    const cmmdAbi = JSON.parse(JSON.stringify(cmmdAbi_json));
    
    // create contract instance
    const cmmdAddress = "0x566Bf25BA5ff47fBF179977b4CC8d8cF23fC76eF";
    const cmmdContract = new ethers.Contract(cmmdAddress, cmmdAbi, signer);
    policyContract.initialize(cmmdContract, cpi)

    let targetRate =(cpi * Math.pow(10,18))/cpi

    console.log("target market price given latest cpi: " +targetRate);
    policyContract.rebase();
    const newmarket = await marketOracle.getData().then(result => result[0]._hex)
    console.log("rebased market price: "+ hexToDecimal(newmarket));
    if((Math.abs(hexToDecimal(newmarket) - targetRate)) < (5*Math.pow(10,16)))
    {
      console.log("Difference between target market price and rebased market price is smaller than deviation threshold");
      return true
    }
    else
    {
      console.log("Difference between target market price and rebased market price is greater than deviation threshold");
      return false
    } 

  
}


  describe('Policy Simulation', function () {
    it('should successfully run simulation', async function () {
      expect(await exec()).equal(true)

    })
  })
