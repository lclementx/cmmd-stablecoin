import { ethers, upgrades } from 'hardhat'
import { expect } from 'chai'
//import {CMMD} from "./CMMD.sol";

async function exec() {


        const [deployer] = await ethers.getSigners()
        
        const CMMD = await ethers.getContractFactory("CMMD");
        const myCMMD = await CMMD.deploy();
        await myCMMD.deployed();
        await myCMMD.setMonetaryPolicy(deployer.getAddress())


        const endSupply = ethers.BigNumber.from(2).pow(128).sub(1)
        let preRebaseSupply = ethers.BigNumber.from(0),
          postRebaseSupply = ethers.BigNumber.from(0)
      
        let i = 0
        do {
          console.log('Iteration', i + 1)
      
          preRebaseSupply = await myCMMD.totalSupply()

          await myCMMD.connect(deployer).rebase(2 * i, 1)
          postRebaseSupply = await myCMMD.totalSupply()
          console.log('Rebase by doubling supply')
          console.log('Total supply is now', postRebaseSupply.toString(), 'CMMD')

          expect(postRebaseSupply.sub(preRebaseSupply).toNumber()).to.eq(1)
    
          await myCMMD.connect(deployer).rebase(2 * i + 1, postRebaseSupply)

          i++
        } while ((await myCMMD.totalSupply()).lt(endSupply))
}


  describe('Supply Precision', function () {
    it('should successfully run simulation', async function () {
      await exec()
    })
  })